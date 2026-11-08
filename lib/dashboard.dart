import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'assignments.dart' hide ApiService;
import 'change-password.dart';
import 'notes.dart';
import 'service.dart';
import 'main.dart' show LoginPage;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;
  bool _isOpeningTextbook = false;
  bool _isDownloadingTextbook = false;

  static const Color primaryColor = Color(0xFF0D9488);
  static const Color backgroundColor = Color(0xFFF5F8FA);

  static const String _textbookBaseUrl = 'https://www.learnit.com.et/api/';

  Map<String, dynamic> get _student {
    return ApiService.student ?? {};
  }

  String get _studentName {
    return _student['full_name']?.toString() ?? 'Student';
  }

  String get _studentGrade {
    final grade = _student['grade']?.toString() ?? '';
    final section = _student['section']?.toString() ?? '';

    if (grade.isEmpty) return 'Student';

    return section.isEmpty ? 'Grade $grade' : 'Grade $grade • Section $section';
  }

  String? get _textbookFile {
    final grade = _student['grade']?.toString() ?? '';
    final match = RegExp(r'\d+').firstMatch(grade);
    final gradeNumber = match?.group(0);

    if (gradeNumber == '7') return 'Grade7.pdf';
    if (gradeNumber == '8') return 'Grade8.pdf';

    return null;
  }

  String get _textbookTitle {
    switch (_textbookFile) {
      case 'Grade7.pdf':
        return 'Grade 7 Textbook';
      case 'Grade8.pdf':
        return 'Grade 8 Textbook';
      default:
        return 'Textbook unavailable';
    }
  }

  String get _textbookFileName {
    return _textbookFile?.replaceFirst('.pdf', '') ?? 'Textbook';
  }

  String get _studentInitials {
    final name = _studentName.trim();

    if (name.isEmpty || name == 'Student') return 'S';

    final parts = name.split(RegExp(r'\s+'));

    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  bool _hasPdfSignature(Uint8List bytes) {
    return bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;
  }

  Future<Uint8List> _loadTextbookBytes() async {
    final fileName = _textbookFile;

    if (fileName == null) {
      throw Exception('A textbook is available for Grades 7 and 8 only.');
    }

    final uri = Uri.parse('$_textbookBaseUrl$fileName');

    final response = await http
        .get(uri, headers: const {'Accept': 'application/pdf'})
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception(
        'Unable to load $fileName. '
        'HTTP ${response.statusCode}. '
        'Please check the PDF URL on your server.',
      );
    }

    final bytes = response.bodyBytes;

    if (!_hasPdfSignature(bytes)) {
      final preview = String.fromCharCodes(bytes.take(100).toList());

      throw Exception(
        'The server did not return a valid PDF. '
        'Content-Type: ${response.headers['content-type'] ?? 'unknown'}. '
        'Response: $preview',
      );
    }

    return bytes;
  }

  Future<void> _viewTextbook() async {
    if (_textbookFile == null || _isOpeningTextbook || _isDownloadingTextbook) {
      return;
    }

    setState(() {
      _isOpeningTextbook = true;
    });

    try {
      final bytes = await _loadTextbookBytes();

      if (!mounted) return;

      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => NotePdfPage(title: _textbookTitle, pdfBytes: bytes),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      _showTextbookMessage(
        'Unable to open textbook: '
        '${e.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningTextbook = false;
        });
      }
    }
  }

  Future<void> _downloadTextbook() async {
    if (_textbookFile == null || _isDownloadingTextbook || _isOpeningTextbook) {
      return;
    }

    setState(() {
      _isDownloadingTextbook = true;
    });

    try {
      final bytes = await _loadTextbookBytes();

      if (!mounted) return;

      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save textbook PDF',
        fileName: '$_textbookFileName.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );

      if (!mounted) return;

      if (savedPath == null || savedPath.toString().isEmpty) {
        _showTextbookMessage('PDF saving was cancelled.');
        return;
      }

      _showTextbookMessage('Textbook saved successfully.');
    } catch (e) {
      if (!mounted) return;

      _showTextbookMessage(
        'Unable to save textbook: '
        '${e.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingTextbook = false;
        });
      }
    }
  }

  void _showTextbookMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Colors.red.shade700 : primaryColor,
        ),
      );
  }

  Future<void> _openChangePassword() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
    );

    if (!mounted) return;

    setState(() {
      _selectedIndex = 0;
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to log out of LearnIT?'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: primaryColor),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    ApiService.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _onNavigationTap(int index) {
    if (index == 3) {
      _openChangePassword();
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildHomePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My Learning',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF172B4D),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Welcome back! Keep learning every day.',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hello,',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _studentName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _studentGrade,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white,
                  child: Text(
                    _studentInitials,
                    style: const TextStyle(
                      color: primaryColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildTextbookCard(),
        ],
      ),
    );
  }

  Widget _buildTextbookCard() {
    final hasTextbook = _textbookFile != null;
    final isBusy = _isOpeningTextbook || _isDownloadingTextbook;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 68,
                height: 82,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: primaryColor,
                  size: 40,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MY TEXTBOOK',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _textbookTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF172B4D),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      hasTextbook
                          ? 'Read and study at your own pace.'
                          : 'Available for Grades 7 and 8.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasTextbook && !isBusy ? _viewTextbook : null,
                  icon: _isOpeningTextbook
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_rounded),
                  label: const Text('View'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: hasTextbook && !isBusy ? _downloadTextbook : null,
                  icon: _isDownloadingTextbook
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(
                    _isDownloadingTextbook ? 'Saving...' : 'Download',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _buildHomePage(),
      const NotesPage(),
      AssignmentsPage(),
    ];

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.school_rounded, color: primaryColor, size: 28),
            SizedBox(width: 10),
            Text(
              'LearnIT',
              style: TextStyle(
                color: Color(0xFF172B4D),
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, size: 19),
            label: const Text('Logout'),
            style: TextButton.styleFrom(foregroundColor: primaryColor),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 16),
            child: CircleAvatar(
              radius: 19,
              backgroundColor: primaryColor.withValues(alpha: 0.12),
              child: Text(
                _studentInitials,
                style: const TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onNavigationTap,
        backgroundColor: Colors.white,
        indicatorColor: primaryColor.withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded),
            label: 'Assignments',
          ),
          NavigationDestination(
            icon: Icon(Icons.lock_outline_rounded),
            selectedIcon: Icon(Icons.lock_rounded),
            label: 'Password',
          ),
        ],
      ),
    );
  }
}
