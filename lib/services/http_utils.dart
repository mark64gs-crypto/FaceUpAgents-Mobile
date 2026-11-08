import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isAuthorizationError => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> requestJson(
  http.Client client,
  String method,
  Uri uri, {
  Map<String, String> headers = const {},
  Object? body,
  Duration timeout = const Duration(seconds: 90),
}) async {
  try {
    final request = http.Request(method, uri);
    request.headers.addAll(headers);
    if (body != null) {
      request.headers.putIfAbsent(
        HttpHeaders.contentTypeHeader,
        () => 'application/json',
      );
      request.body = jsonEncode(body);
    }
    final streamed = await client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed);
    return decodeResponse(response);
  } on TimeoutException {
    throw const ApiException(
      'The provider took too long to respond. Try again.',
    );
  } on SocketException {
    throw const ApiException(
      'Could not reach the provider. Check your internet connection.',
    );
  } on http.ClientException {
    throw const ApiException(
      'Could not reach the provider. Check your internet connection.',
    );
  }
}

Future<http.Response> rawRequest(
  http.Client client,
  http.BaseRequest request, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  try {
    final streamed = await client.send(request).timeout(timeout);
    return await http.Response.fromStream(streamed).timeout(timeout);
  } on TimeoutException {
    throw const ApiException(
      'The provider took too long to respond. Try again.',
    );
  } on SocketException {
    throw const ApiException(
      'Could not reach the provider. Check your internet connection.',
    );
  } on http.ClientException {
    throw const ApiException(
      'Could not reach the provider. Check your internet connection.',
    );
  }
}

Map<String, dynamic> decodeResponse(http.Response response) {
  final text = utf8.decode(response.bodyBytes, allowMalformed: true);
  Map<String, dynamic>? json;
  if (text.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) json = decoded;
    } on FormatException {
      json = null;
    }
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ApiException(
      extractErrorMessage(json) ?? 'HTTP ${response.statusCode}.',
      statusCode: response.statusCode,
    );
  }
  if (json == null) {
    throw ApiException(
      'The provider returned an invalid response (HTTP ${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }
  return json;
}

String? extractErrorMessage(Map<String, dynamic>? json) {
  if (json == null) return null;
  final error = json['error'];
  if (error is String && error.isNotEmpty) return error;
  if (error is Map) {
    final message = error['message'];
    final code = error['code'];
    final metadata = error['metadata'];
    final parts = <String>[];
    if (message is String && message.isNotEmpty) {
      parts.add(message);
    } else if (code is String && code.isNotEmpty) {
      parts.add(code);
    }
    if (metadata is Map) {
      final raw = metadata['raw'];
      if (raw is String && raw.trim().isNotEmpty) parts.add(raw.trim());
      final provider = metadata['provider_name'];
      if (provider is String &&
          provider.trim().isNotEmpty &&
          parts.isNotEmpty) {
        parts.add('Provider: ${provider.trim()}');
      }
    }
    if (parts.isNotEmpty) return parts.join(' — ');
  }
  final message = json['message'];
  if (message is String && message.isNotEmpty) return message;
  final detail = json['detail'];
  if (detail is String && detail.isNotEmpty) return detail;
  return null;
}
