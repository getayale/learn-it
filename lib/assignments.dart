import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'service.dart';

class AssignmentsPage extends StatefulWidget {
  const AssignmentsPage({super.key});

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  static const Color primaryColor = Color(0xFF0D9488);
  static const Color backgroundColor = Color(0xFFF5F8FA);

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;

  String _filter = 'upcoming';
  String? _error;
  List<dynamic> _assignments = [];

  int _currentPage = 1;
  int _lastPage = 1;
  int _totalAssignments = 0;

  @override
  void initState() {
    super.initState();
    _loadAssignments(page: 1);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAssignments({int? page}) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final requestedPage = page ?? _currentPage;

      final response = await ApiService.getAssignments(
        filter: _filter,
        search: _searchController.text.trim(),
        page: requestedPage,
      );

      if (!mounted) return;

      final rawAssignments = response['assignments'];
      final pagination = response['pagination'];

      setState(() {
        _assignments = rawAssignments is List ? rawAssignments : [];

        if (pagination is Map) {
          _currentPage = _toInt(pagination['current_page']) ?? requestedPage;
          _lastPage = _toInt(pagination['last_page']) ?? 1;
          _totalAssignments =
              _toInt(pagination['total']) ?? _assignments.length;
        } else {
          _currentPage = requestedPage;
          _lastPage = 1;
          _totalAssignments = _assignments.length;
        }

        if (_lastPage < 1) _lastPage = 1;
        if (_currentPage < 1) _currentPage = 1;
        if (_currentPage > _lastPage) {
          _currentPage = _lastPage;
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  String _value(dynamic value, {String fallback = '—'}) {
    if (value == null || value.toString().trim().isEmpty) {
      return fallback;
    }

    return value.toString();
  }

  String _title(Map<String, dynamic> assignment) {
    return _value(
      assignment['title'] ?? assignment['assignment_title'],
      fallback: 'Untitled assignment',
    );
  }

  String _description(Map<String, dynamic> assignment) {
    return _value(
      assignment['description'] ?? assignment['instructions'],
      fallback: 'No description provided.',
    );
  }

  Map<String, dynamic>? _submission(Map<String, dynamic> assignment) {
    final value = assignment['submission'];

    if (value is Map<String, dynamic>) return value;

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  bool _isSubmitted(Map<String, dynamic> assignment) {
    if (assignment['has_submission'] == true ||
        assignment['has_submission'] == 1 ||
        assignment['has_submission']?.toString() == '1') {
      return true;
    }

    if (_submission(assignment) != null) return true;

    final status = _value(
      assignment['submission_status'],
      fallback: '',
    ).toLowerCase();

    return status.contains('submitted') ||
        status.contains('graded') ||
        status.contains('completed');
  }

  String _status(Map<String, dynamic> assignment) {
    if (_isSubmitted(assignment)) {
      final submission = _submission(assignment);

      if (submission?['is_late'] == true ||
          submission?['is_late'] == 1 ||
          submission?['is_late']?.toString() == '1') {
        return 'Submitted late';
      }

      return 'Submitted';
    }

    if (_filter == 'past') return 'Not submitted';

    return _value(assignment['submission_status'], fallback: 'Not submitted');
  }

  String _dueDate(Map<String, dynamic> assignment) {
    return _value(
      assignment['due_date'] ??
          assignment['deadline'] ??
          assignment['submission_deadline'],
    );
  }

  Future<void> _search() async {
    await _loadAssignments(page: 1);
  }

  Future<void> _changeFilter(int index) async {
    final newFilter = index == 0 ? 'upcoming' : 'past';

    if (_filter == newFilter) return;

    setState(() {
      _filter = newFilter;
      _currentPage = 1;
      _assignments = [];
    });

    await _loadAssignments(page: 1);
  }

  Future<void> _openAssignment(Map<String, dynamic> assignment) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final submitted = _isSubmitted(assignment);
        final submission = _submission(assignment);

        return AlertDialog(
          title: Text(_title(assignment)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_description(assignment)),
                const SizedBox(height: 18),
                _detailRow('Due date', _dueDate(assignment)),
                _detailRow('Status', _status(assignment)),
                _detailRow(
                  'Subject',
                  _value(assignment['subject_name'] ?? assignment['subject']),
                ),
                _detailRow(
                  'Grade',
                  _value(assignment['grade_name'] ?? assignment['grade']),
                ),
                if (submission != null) ...[
                  const Divider(height: 24),
                  const Text(
                    'Your submission',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _detailRow('File', _value(submission['file_name'])),
                  _detailRow(
                    'Submitted',
                    _value(
                      submission['submitted_at_formatted'] ??
                          submission['submitted_at'],
                    ),
                  ),
                  if (_value(
                    submission['submission_text'],
                    fallback: '',
                  ).isNotEmpty)
                    _detailRow(
                      'Your note',
                      _value(submission['submission_text']),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            if (_filter == 'upcoming')
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _showSubmissionDialog(assignment);
                },
                icon: Icon(
                  submitted ? Icons.refresh_rounded : Icons.upload_file_rounded,
                ),
                label: Text(
                  submitted ? 'Replace submission' : 'Submit assignment',
                ),
                style: FilledButton.styleFrom(backgroundColor: primaryColor),
              ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAssignmentFile({
    required void Function(void Function()) setDialogState,
    required void Function(String message) showError,
    required void Function(Uint8List bytes, String name) onSelected,
  }) async {
    try {
      final file = await FilePicker.pickFile(type: FileType.any);

      if (!mounted || file == null) return;

      final bytes = await file.readAsBytes();

      if (!mounted) return;

      if (bytes.isEmpty) {
        showError('Unable to read this file. Please choose it again.');
        return;
      }

      final name = file.name.trim();

      if (name.isEmpty) {
        showError('The selected file has no valid filename.');
        return;
      }

      setDialogState(() {
        onSelected(bytes, name);
      });
    } catch (e) {
      showError(
        'Could not select file: '
        '${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  Future<void> _showSubmissionDialog(Map<String, dynamic> assignment) async {
    final assignmentId = _toInt(
      assignment['id'] ?? assignment['assignment_id'],
    );

    if (assignmentId == null) {
      _showMessage('This assignment has no valid ID.');
      return;
    }

    final textController = TextEditingController();
    final existingSubmission = _submission(assignment);

    Uint8List? fileBytes;
    String? fileName;
    bool dialogSubmitting = false;

    if (existingSubmission != null) {
      textController.text = _value(
        existingSubmission['submission_text'],
        fallback: '',
      );
    }

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final replacing = _isSubmitted(assignment);

              return AlertDialog(
                title: Text(
                  replacing ? 'Replace Submission' : 'Submit Assignment',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(assignment),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      if (replacing) ...[
                        const Text(
                          'Your current submission will be replaced after '
                          'the new file is uploaded successfully.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: textController,
                        enabled: !dialogSubmitting,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'Submission note (optional)',
                          hintText: 'Write a short message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: dialogSubmitting
                            ? null
                            : () async {
                                await _pickAssignmentFile(
                                  setDialogState: setDialogState,
                                  showError: _showMessage,
                                  onSelected: (bytes, name) {
                                    fileBytes = bytes;
                                    fileName = name;
                                  },
                                );
                              },
                        icon: const Icon(Icons.attach_file_rounded),
                        label: SizedBox(
                          width: 180,
                          child: Text(
                            fileName ??
                                (replacing
                                    ? 'Choose replacement file'
                                    : 'Choose file'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (fileName != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Selected: $fileName',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'Maximum file size: 10 MB.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: dialogSubmitting
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: dialogSubmitting
                        ? null
                        : () async {
                            if (fileBytes == null || fileName == null) {
                              _showMessage('Please choose a file first.');
                              return;
                            }

                            setDialogState(() {
                              dialogSubmitting = true;
                            });

                            final success = await _submitFile(
                              assignmentId: assignmentId,
                              fileBytes: fileBytes!,
                              fileName: fileName!,
                              submissionText: textController.text.trim(),
                            );

                            if (!dialogContext.mounted) return;

                            if (success) {
                              Navigator.pop(dialogContext);
                            } else {
                              setDialogState(() {
                                dialogSubmitting = false;
                              });
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                    ),
                    child: dialogSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(replacing ? 'Replace file' : 'Submit'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      textController.dispose();
    }
  }

  Future<bool> _submitFile({
    required int assignmentId,
    required Uint8List fileBytes,
    required String fileName,
    required String submissionText,
  }) async {
    if (!mounted) return false;

    setState(() {
      _error = null;
    });

    try {
      final response = await ApiService.submitAssignment(
        assignmentId: assignmentId,
        fileBytes: fileBytes,
        fileName: fileName,
        submissionText: submissionText,
      );

      if (!mounted) return false;

      _showMessage(
        _value(
          response['message'],
          fallback: 'Assignment submitted successfully.',
        ),
      );

      await _loadAssignments(page: _currentPage);

      return true;
    } catch (e) {
      if (!mounted) return false;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });

      _showMessage(_error!);

      return false;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Color _statusColor(String status) {
    final value = status.toLowerCase();

    if (value.contains('submitted')) {
      return const Color(0xFF15803D);
    }

    if (value.contains('graded') || value.contains('completed')) {
      return const Color(0xFF15803D);
    }

    if (value.contains('late') || value.contains('overdue')) {
      return const Color(0xFFDC2626);
    }

    return const Color(0xFFB45309);
  }

  Widget _buildStatusChip(String status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> assignment) {
    final status = _status(assignment);

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE8EDF2)),
      ),
      child: InkWell(
        onTap: () => _openAssignment(assignment),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.assignment_outlined,
                      color: primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title(assignment),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF172B4D),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _value(
                            assignment['subject_name'] ?? assignment['subject'],
                            fallback: 'General subject',
                          ),
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: _buildStatusChip(status)),
                ],
              ),
              const SizedBox(height: 15),
              Text(
                _description(assignment),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  height: 1.5,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  const Icon(
                    Icons.event_outlined,
                    size: 17,
                    color: Colors.black45,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Due: ${_dueDate(assignment)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openAssignment(assignment),
                    child: Text(
                      _isSubmitted(assignment)
                          ? 'View details'
                          : 'View / Submit',
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

  Widget _buildPastAssignmentsTable() {
    final assignments = _assignments
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text(
          'Past assignments',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF172B4D),
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Assignments whose deadlines have passed.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (assignments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 54, color: Colors.black26),
                SizedBox(height: 12),
                Text(
                  'No past assignments found.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          )
        else
          Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF0FDFA),
                ),
                columnSpacing: 22,
                horizontalMargin: 14,
                columns: const [
                  DataColumn(label: Text('Assignment')),
                  DataColumn(label: Text('Subject')),
                  DataColumn(label: Text('Due date')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Action')),
                ],
                rows: assignments.map((assignment) {
                  final status = _status(assignment);

                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 170,
                          child: Text(
                            _title(assignment),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: Text(
                            _value(
                              assignment['subject_name'] ??
                                  assignment['subject'],
                              fallback: '—',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(_dueDate(assignment))),
                      DataCell(_buildStatusChip(status)),
                      DataCell(
                        TextButton(
                          onPressed: () => _openAssignment(assignment),
                          child: const Text('Details'),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        _buildPagination(),
      ],
    );
  }

  Widget _buildPagination() {
    if (_lastPage <= 1) {
      if (_totalAssignments > 0) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              '$_totalAssignments assignment'
              '${_totalAssignments == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
        );
      }

      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: _currentPage > 1 && !_isLoading
                ? () => _loadAssignments(page: _currentPage - 1)
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text(
            'Page $_currentPage of $_lastPage',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: _currentPage < _lastPage && !_isLoading
                ? () => _loadAssignments(page: _currentPage + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: primaryColor),
      );
    }

    if (_error != null && _assignments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: Colors.black38,
              ),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _loadAssignments(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
                style: FilledButton.styleFrom(backgroundColor: primaryColor),
              ),
            ],
          ),
        ),
      );
    }

    if (_filter == 'past') {
      return RefreshIndicator(
        onRefresh: () => _loadAssignments(page: _currentPage),
        child: _buildPastAssignmentsTable(),
      );
    }

    if (_assignments.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadAssignments(page: _currentPage),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(28),
          children: const [
            SizedBox(height: 80),
            Icon(Icons.assignment_outlined, size: 60, color: Colors.black26),
            SizedBox(height: 16),
            Center(
              child: Text(
                'No ongoing assignments found.',
                style: TextStyle(color: Colors.black54, fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadAssignments(page: _currentPage),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (final item in _assignments)
            if (item is Map<String, dynamic>) _buildAssignmentCard(item),
          _buildPagination(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Container(
        color: backgroundColor,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'My Assignments',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF172B4D),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _isLoading
                            ? null
                            : () => _loadAssignments(page: _currentPage),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$_totalAssignments assignment'
                    '${_totalAssignments == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'Search assignments...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Search',
                        onPressed: _search,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    onTap: _changeFilter,
                    labelColor: primaryColor,
                    unselectedLabelColor: Colors.black54,
                    indicatorColor: primaryColor,
                    indicatorWeight: 3,
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.pending_actions_rounded),
                        text: 'Ongoing',
                      ),
                      Tab(
                        icon: Icon(Icons.history_rounded),
                        text: 'Passed deadline',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}
