import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'http_client_factory.dart';

class ApiService {
  static const String _baseUrl = 'https://www.learnit.com.et/api/';

  static final http.Client _client = createHttpClient();

  static String? _sessionCookie;

  static Map<String, dynamic>? student;

  static Map<String, String> get _headers {
    final headers = <String, String>{'Accept': 'application/json'};

    // Native apps must send the PHP session cookie explicitly.
    // Web browsers manage cookies through BrowserClient credentials.
    if (!kIsWeb && _sessionCookie != null) {
      headers['Cookie'] = _sessionCookie!;
    }

    return headers;
  }

  /*
  |--------------------------------------------------------------------------
  | Session Cookie
  |--------------------------------------------------------------------------
  */

  static void _saveSessionCookie(http.Response response) {
    // Browsers manage cookies automatically. Do not read or set them here.
    if (kIsWeb) return;

    final setCookie = response.headers['set-cookie'];

    if (setCookie == null || setCookie.isEmpty) {
      return;
    }

    // Capture the PHP session cookie without its attributes.
    final match = RegExp(r'(?:^|,\s*)(PHPSESSID=[^;,\s]+)')
        .firstMatch(setCookie);

    if (match != null) {
      _sessionCookie = match.group(1);
      debugPrint('PHP session cookie received.');
    }
  }

  /*
  |--------------------------------------------------------------------------
  | Authentication
  |--------------------------------------------------------------------------
  */

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final url = Uri.parse('${_baseUrl}login.php');

    // Remove the previous local session before a new login attempt.
    _sessionCookie = null;
    student = null;

    try {
      final response = await _client
          .post(
            url,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'username': username.trim(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final data = _decodeResponse(response.body);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        final returnedStudent = data['student'];

        if (returnedStudent is! Map<String, dynamic>) {
          throw Exception(
            'The server response is missing student information.',
          );
        }

        _saveSessionCookie(response);

        student = returnedStudent;

        debugPrint('Login successful.');
        debugPrint('Platform: ${kIsWeb ? 'Web' : 'Native'}');

        if (!kIsWeb && _sessionCookie == null) {
          debugPrint(
            'Warning: No PHPSESSID cookie was found in the login response.',
          );
        }

        return data;
      }

      throw _serverError(data, 'Login failed. Please check your credentials.');
    } on TimeoutException {
      throw Exception('The server took too long to respond. Please try again.');
    } on http.ClientException {
      throw Exception('Unable to connect to the server. Please try again.');
    } on FormatException {
      throw Exception('Invalid server response. Please try again.');
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }

      throw Exception('Something went wrong. Please try again.');
    }
  }

  static void logout() {
    _sessionCookie = null;
    student = null;

    debugPrint('Local student information and session cookie cleared.');
  }

  /*
  |--------------------------------------------------------------------------
  | Helpers
  |--------------------------------------------------------------------------
  */

  static Map<String, dynamic> _decodeResponse(String body) {
    final decoded = jsonDecode(body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid response format.');
    }

    return decoded;
  }

  static Exception _serverError(Map<String, dynamic> data, String fallback) {
    final message = data['message'];

    if (message is String && message.isNotEmpty) {
      return Exception(message);
    }

    return Exception(fallback);
  }

  static Exception _authenticationError(Map<String, dynamic> data) {
    if (data['code'] == 'PASSWORD_CHANGE_REQUIRED') {
      return Exception('Please change your password before continuing.');
    }

    return _serverError(data, 'Your session has expired. Please log in again.');
  }

  /*
  |--------------------------------------------------------------------------
  | Notes Endpoints
  |--------------------------------------------------------------------------
  */

  static Future<Map<String, dynamic>> getNotes({
    String? search,
    String? unit,
    int? noteId,
  }) async {
    final queryParameters = <String, String>{};

    if (search != null && search.trim().isNotEmpty) {
      queryParameters['search'] = search.trim();
    }

    if (unit != null && unit.isNotEmpty) {
      queryParameters['unit'] = unit;
    }

    if (noteId != null) {
      queryParameters['note'] = noteId.toString();
    }

    final uri = Uri.parse('${_baseUrl}notes.php').replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );

    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 25));

      _saveSessionCookie(response);

      final data = _decodeResponse(response.body);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        return data;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw _authenticationError(data);
      }

      throw _serverError(data, 'Unable to load notes. Please try again.');
    } on TimeoutException {
      throw Exception('The server took too long to respond. Please try again.');
    } on http.ClientException {
      throw Exception('Unable to connect to the server. Please try again.');
    } on FormatException {
      throw Exception('Invalid server response. Please try again.');
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }

      throw Exception('Something went wrong. Please try again.');
    }
  }

  static Future<Uint8List> getNotePdf({
    required int noteId,
    bool download = false,
  }) async {
    final queryParameter = download ? 'download' : 'view';

    final uri = Uri.parse('${_baseUrl}notes.php')
        .replace(queryParameters: {queryParameter: noteId.toString()});

    try {
      final response = await _client
          .get(uri, headers: {..._headers, 'Accept': 'application/pdf'})
          .timeout(const Duration(seconds: 60));

      _saveSessionCookie(response);

      final contentType = response.headers['content-type']?.toLowerCase() ?? '';

      if (response.statusCode == 200 &&
          contentType.contains('application/pdf')) {
        return response.bodyBytes;
      }

      var message = 'Unable to open this PDF. Please try again.';

      try {
        final data = _decodeResponse(response.body);

        final serverMessage = data['message'];

        if (serverMessage is String && serverMessage.isNotEmpty) {
          message = serverMessage;
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          throw _authenticationError(data);
        }
      } on FormatException {
        // Keep the default message for non-JSON responses.
      }

      throw Exception(message);
    } on TimeoutException {
      throw Exception('The PDF took too long to load. Please try again.');
    } on http.ClientException {
      throw Exception('Unable to connect to the server. Please try again.');
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }

      throw Exception('Unable to open this PDF. Please try again.');
    }
  }

  /*
  |--------------------------------------------------------------------------
  | Assignments Endpoints
  |--------------------------------------------------------------------------
  */

  static Future<Map<String, dynamic>> getAssignments({
    String filter = 'all',
    String search = '',
    int page = 1,
  }) async {
    final uri = Uri.parse('${_baseUrl}assignments.php').replace(
      queryParameters: {
        'filter': filter,
        'search': search.trim(),
        'page': page.toString(),
      },
    );

    try {
      debugPrint('Assignments URL: $uri');

      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));

      _saveSessionCookie(response);

      debugPrint('Assignments status: ${response.statusCode}');

      final data = _decodeResponse(response.body);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        return data;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw _authenticationError(data);
      }

      throw _serverError(data, 'Unable to load assignments.');
    } on TimeoutException {
      throw Exception('The server took too long to respond. Please try again.');
    } on http.ClientException {
      throw Exception('Unable to connect to the server.');
    } on FormatException {
      throw Exception('Invalid server response.');
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }

      throw Exception('Unable to load assignments.');
    }
  }

  static Future<Map<String, dynamic>> submitAssignment({
    required int assignmentId,
    required Uint8List fileBytes,
    required String fileName,
    String submissionText = '',
  }) async {
    final uri = Uri.parse('${_baseUrl}assignments.php');

    try {
      final request = http.MultipartRequest('POST', uri);

      request.headers.addAll(_headers);

      request.fields['assignment_id'] = assignmentId.toString();
      request.fields['submission_text'] = submissionText;

      request.files.add(
        http.MultipartFile.fromBytes(
          'submission_file',
          fileBytes,
          filename: fileName,
        ),
      );

      final streamedResponse = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));

      final response = await http.Response.fromStream(streamedResponse);

      _saveSessionCookie(response);

      debugPrint('Submission status: ${response.statusCode}');

      final data = _decodeResponse(response.body);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        return data;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw _authenticationError(data);
      }

      throw _serverError(data, 'Unable to submit your assignment.');
    } on TimeoutException {
      throw Exception(
        'The submission took too long. '
        'Please check your connection and try again.',
      );
    } on http.ClientException {
      throw Exception('Unable to connect to the server.');
    } on FormatException {
      throw Exception('Invalid server response.');
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }

      throw Exception('Unable to submit your assignment.');
    }
  }

  /*
  |--------------------------------------------------------------------------
  | Change Password Endpoint
  |--------------------------------------------------------------------------
  */

  static Future<http.Response> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final uri = Uri.parse('${_baseUrl}change-password.php');

    try {
      final response = await _client
          .post(
            uri,
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'current_password': currentPassword,
              'new_password': newPassword,
              'confirm_password': confirmPassword,
            }),
          )
          .timeout(const Duration(seconds: 20));

      _saveSessionCookie(response);

      return response;
    } on TimeoutException {
      throw Exception('The server took too long to respond. Please try again.');
    } on http.ClientException {
      throw Exception('Unable to connect to the server. Please try again.');
    }
  }
}
