import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import 'service.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;

  String _selectedUnit = '';
  String _studentName = 'Student';
  String _grade = '';
  String _section = '';

  String? _errorMessage;

  int _totalNotes = 0;
  int _totalUnits = 0;
  int? _openingNoteId;
  int? _downloadingNoteId;
  int _requestId = 0;

  List<int> _unitNumbers = [];

  Map<int, List<Map<String, dynamic>>> _notesByUnit = {};

  @override
  void initState() {
    super.initState();
    _loadNotes(updateUnits: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes({bool updateUnits = false}) async {
    if (!mounted) return;

    final requestId = ++_requestId;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.getNotes(
        search: _searchController.text.trim(),
        unit: _selectedUnit.isEmpty ? null : _selectedUnit,
      );

      if (result['success'] != true) {
        throw Exception(
          result['message']?.toString() ?? 'Unable to load notes.',
        );
      }

      final studentData = Map<String, dynamic>.from(
        result['student'] as Map? ?? {},
      );

      final statistics = Map<String, dynamic>.from(
        result['statistics'] as Map? ?? {},
      );

      final units = (result['units'] as List? ?? [])
          .whereType<Map>()
          .map((unit) => Map<String, dynamic>.from(unit))
          .toList();

      final availableUnits = (result['available_units'] as List? ?? [])
          .whereType<Map>()
          .map((unit) => Map<String, dynamic>.from(unit))
          .toList();

      final groupedNotes = <int, List<Map<String, dynamic>>>{};

      for (final unit in units) {
        final unitNumber = int.tryParse('${unit['unit_number']}');

        if (unitNumber == null) continue;

        final unitNotes = (unit['notes'] as List? ?? [])
            .whereType<Map>()
            .map((note) => Map<String, dynamic>.from(note))
            .toList();

        groupedNotes.putIfAbsent(unitNumber, () => []);
        groupedNotes[unitNumber]!.addAll(unitNotes);
      }

      for (final notes in groupedNotes.values) {
        notes.sort((a, b) {
          final firstTitle = a['title']?.toString() ?? '';
          final secondTitle = b['title']?.toString() ?? '';

          return firstTitle.toLowerCase().compareTo(secondTitle.toLowerCase());
        });
      }

      final sortedUnitNumbers = groupedNotes.keys.toList()..sort();

      final availableUnitNumbers =
          availableUnits
              .map((unit) => int.tryParse('${unit['unit_number']}'))
              .whereType<int>()
              .toSet()
              .toList()
            ..sort();

      if (!mounted || requestId != _requestId) return;

      setState(() {
        _studentName = studentData['full_name']?.toString() ?? 'Student';
        _grade = studentData['grade']?.toString() ?? '';
        _section = studentData['section']?.toString() ?? '';

        _totalNotes = int.tryParse('${statistics['total_notes']}') ?? 0;
        _totalUnits = int.tryParse('${statistics['total_units']}') ?? 0;

        _notesByUnit = {
          for (final unitNumber in sortedUnitNumbers)
            unitNumber: groupedNotes[unitNumber]!,
        };

        if (updateUnits || _unitNumbers.isEmpty) {
          _unitNumbers = availableUnitNumbers;
        }

        if (_selectedUnit.isNotEmpty &&
            !_unitNumbers.contains(int.tryParse(_selectedUnit))) {
          _selectedUnit = '';
        }

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _searchNotes() async {
    FocusScope.of(context).unfocus();
    await _loadNotes(updateUnits: _selectedUnit.isEmpty);
  }

  Future<void> _changeUnit(String? value) async {
    if (value == null || value == _selectedUnit) return;

    setState(() {
      _selectedUnit = value;
    });

    await _loadNotes();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? Colors.red.shade700
              : const Color(0xFF0D9488),
        ),
      );
  }

  bool _hasPdfSignature(Uint8List bytes) {
    return bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;
  }

  Future<void> _openPdf(Map<String, dynamic> note) async {
    final noteId = int.tryParse('${note['id']}');

    if (noteId == null ||
        _openingNoteId != null ||
        _downloadingNoteId != null) {
      return;
    }

    setState(() {
      _openingNoteId = noteId;
    });

    try {
      final Uint8List pdfBytes = await ApiService.getNotePdf(noteId: noteId);

      if (!mounted) return;

      if (!_hasPdfSignature(pdfBytes)) {
        throw Exception('The server did not return a valid PDF file.');
      }

      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) => NotePdfPage(
            title: note['title']?.toString() ?? 'Lesson PDF',
            pdfBytes: pdfBytes,
          ),
        ),
      );
    } catch (e) {
      _showMessage(
        'Unable to open PDF: '
        '${e.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingNoteId = null;
        });
      }
    }
  }

  Future<void> _downloadPdf(Map<String, dynamic> note) async {
    final noteId = int.tryParse('${note['id']}');

    if (noteId == null ||
        _downloadingNoteId != null ||
        _openingNoteId != null) {
      return;
    }

    setState(() {
      _downloadingNoteId = noteId;
    });

    try {
      final Uint8List pdfBytes = await ApiService.getNotePdf(
        noteId: noteId,
        download: true,
      );

      if (!mounted) return;

      if (!_hasPdfSignature(pdfBytes)) {
        throw Exception('The server did not return a valid PDF file.');
      }

      final safeTitle = (note['title']?.toString() ?? 'lesson')
          .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
          .trim();

      final filename = '${safeTitle.isEmpty ? 'lesson' : safeTitle}.pdf';

      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save lesson PDF',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: pdfBytes,
      );

      if (!mounted) return;

      if (savedPath == null || savedPath.toString().isEmpty) {
        _showMessage('PDF saving was cancelled.');
        return;
      }

      _showMessage('PDF saved successfully.');
    } catch (e) {
      _showMessage(
        'Unable to save PDF: '
        '${e.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingNoteId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      appBar: AppBar(
        title: const Text(
          'My Notes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh notes',
            onPressed: _isLoading
                ? null
                : () => _loadNotes(updateUnits: _selectedUnit.isEmpty),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStudentHeader(),
            _buildSearchAndFilter(),
            Expanded(child: _buildNotesContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF0D9488),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _studentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                [
                  if (_grade.isNotEmpty) 'Grade $_grade',
                  if (_section.isNotEmpty) 'Section $_section',
                ].join(' • '),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.menu_book_rounded,
                      value: '$_totalNotes',
                      label: 'Lessons',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.folder_copy_rounded,
                      value: '$_totalUnits',
                      label: 'Units',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 25),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchNotes(),
                decoration: InputDecoration(
                  hintText: 'Search lesson titles...',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF0D9488),
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: _isLoading ? null : _searchNotes,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF0D9488),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.filter_list_rounded,
                    size: 20,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Filter by unit',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 145,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedUnit,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('All units'),
                        ),
                        ..._unitNumbers.map(
                          (unit) => DropdownMenuItem<String>(
                            value: unit.toString(),
                            child: Text('Unit $unit'),
                          ),
                        ),
                      ],
                      onChanged: _isLoading ? null : _changeUnit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0D9488)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadNotes(updateUnits: _selectedUnit.isEmpty),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_notesByUnit.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF0D9488),
        onRefresh: () => _loadNotes(updateUnits: _selectedUnit.isEmpty),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 75),
            Icon(
              Icons.menu_book_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'No notes found',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try another search or select a different unit.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final unitNumbers = _notesByUnit.keys.toList()..sort();

    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth < 600 ? 12.0 : 24.0;

    return RefreshIndicator(
      color: const Color(0xFF0D9488),
      onRefresh: () => _loadNotes(updateUnits: _selectedUnit.isEmpty),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          8,
          horizontalPadding,
          24,
        ),
        itemCount: unitNumbers.length,
        itemBuilder: (context, index) {
          final unitNumber = unitNumbers[index];
          final unitNotes = _notesByUnit[unitNumber]!;

          return _buildUnitSection(
            unitNumber: unitNumber,
            notes: unitNotes,
            initiallyExpanded: index == 0,
          );
        },
      ),
    );
  }

  Widget _buildUnitSection({
    required int unitNumber,
    required List<Map<String, dynamic>> notes,
    required bool initiallyExpanded,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ExpansionTile(
        key: PageStorageKey<String>('notes-unit-$unitNumber'),
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2F1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.folder_open_rounded,
            color: Color(0xFF0D9488),
          ),
        ),
        title: Text(
          'Unit $unitNumber',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF172B4D),
          ),
        ),
        subtitle: Text(
          '${notes.length} ${notes.length == 1 ? 'lesson' : 'lessons'}',
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
        children: [for (final note in notes) _buildNoteCard(note)],
      ),
    );
  }

  Widget _buildNoteCard(Map<String, dynamic> note) {
    final title = note['title']?.toString() ?? 'Untitled lesson';
    final fileName = note['file_name']?.toString() ?? 'Lesson file';
    final fileSize = note['file_size_formatted']?.toString() ?? '';
    final isPdf = note['is_pdf'] == true;
    final noteId = int.tryParse('${note['id']}');

    final isOpening = _openingNoteId == noteId;
    final isDownloading = _downloadingNoteId == noteId;
    final isBusy = _openingNoteId != null || _downloadingNoteId != null;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EDF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isPdf
                    ? Icons.picture_as_pdf_rounded
                    : Icons.insert_drive_file_outlined,
                color: const Color(0xFF0D9488),
                size: 25,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: isPdf && noteId != null && !isBusy
                    ? () => _openPdf(note)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF172B4D),
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (fileSize.isNotEmpty)
                        Text(
                          fileSize,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      const SizedBox(height: 3),
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (isPdf) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Open PDF',
                onPressed: noteId == null || isBusy
                    ? null
                    : () => _openPdf(note),
                icon: isOpening
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF0D9488),
                        ),
                      )
                    : const Icon(
                        Icons.visibility_rounded,
                        color: Color(0xFF0D9488),
                      ),
              ),
              IconButton(
                tooltip: 'Save PDF',
                onPressed: noteId == null || isBusy
                    ? null
                    : () => _downloadPdf(note),
                icon: isDownloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF0D9488),
                        ),
                      )
                    : const Icon(
                        Icons.download_rounded,
                        color: Color(0xFF0D9488),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NotePdfPage extends StatefulWidget {
  const NotePdfPage({super.key, required this.title, required this.pdfBytes});

  final String title;
  final Uint8List pdfBytes;

  @override
  State<NotePdfPage> createState() => _NotePdfPageState();
}

class _NotePdfPageState extends State<NotePdfPage> {
  late final PdfControllerPinch _pdfController;

  Object? _documentError;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfControllerPinch(document: _openDocument());
  }

  Future<PdfDocument> _openDocument() async {
    try {
      final bytes = widget.pdfBytes;

      if (bytes.isEmpty) {
        throw Exception('The PDF file contains no data.');
      }

      if (bytes.length < 5 ||
          bytes[0] != 0x25 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x44 ||
          bytes[3] != 0x46 ||
          bytes[4] != 0x2D) {
        throw Exception(
          'The response does not begin with a PDF signature (%PDF-).',
        );
      }

      return await PdfDocument.openData(bytes);
    } catch (error, stackTrace) {
      debugPrint('Failed to initialize PDF document: $error');
      debugPrintStack(stackTrace: stackTrace);

      _documentError = error;
      rethrow;
    }
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: PdfViewPinch(
            controller: _pdfController,
            builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
              options: const DefaultBuilderOptions(),
              documentLoaderBuilder: (_) => const Center(
                child: CircularProgressIndicator(color: Color(0xFF0D9488)),
              ),
              pageLoaderBuilder: (_) => const Center(
                child: CircularProgressIndicator(color: Color(0xFF0D9488)),
              ),
              errorBuilder: (_, error) {
                final details = _documentError?.toString() ?? error.toString();

                debugPrint('PDF viewer error: $details');

                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 52,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Unable to display this PDF.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(details, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Back to notes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
