import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:traceit_app/const.dart';
import 'package:traceit_app/storage/storage.dart';

class ServerAuth {
  static final Storage _storage = Storage();

  static Future<int> register(
    String username,
    String password,
    String email,
    String phoneNumber,
  ) async {
    http.Response response = await http.post(
      Uri.parse('$serverUrl/auth/register'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'username': username,
        'password': password,
        'email': email,
        'phone_number': phoneNumber,
      }),
    );

    debugPrint('Signup response code: ${response.statusCode.toString()}');
    debugPrint('Response body: ${response.body}');

    return response.statusCode;
  }

  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    http.Response response = await http.post(
      Uri.parse('$serverUrl/auth/login'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'username': username,
        'password': password,
      }),
    );

    debugPrint(response.body);

    Map<String, dynamic> loginStatus = {
      'statusCode': response.statusCode,
    };

    if (response.statusCode == 200) {
      Map<String, dynamic> responseBody = jsonDecode(response.body);

      bool hasOtp = responseBody['user']['has_otp'] as bool;
      String tempAccessToken =
          responseBody['user']['tokens']['access'] as String;
      String tempRefreshToken =
          responseBody['user']['tokens']['refresh'] as String;

      loginStatus['hasOtp'] = hasOtp;
      loginStatus['tempAccessToken'] = tempAccessToken;
      loginStatus['tempRefreshToken'] = tempRefreshToken;
    }

    return loginStatus;
  }

  static Future<http.Response> refreshToken(String refreshToken) async {
    http.Response response = await http.post(
      Uri.parse('$serverUrl/auth/refresh'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'refresh': refreshToken,
      }),
    );

    return response;
  }

  static Future<Map<String, String>?> getTokens() async {
    Map<String, String?> tokens = await _storage.getTokens();
    String? accessToken = tokens['accessToken'];
    String? refreshToken = tokens['refreshToken'];

    if (accessToken == null || refreshToken == null) {
      // No tokens stored
      return null;
    } else if (!JwtDecoder.isExpired(accessToken) &&
        !JwtDecoder.isExpired(refreshToken)) {
      // Tokens are not expired and valid
      return {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      };
    }

    // Tokens are expired
    // Refresh tokens
    http.Response response = await ServerAuth.refreshToken(refreshToken);

    if (response.statusCode == 200) {
      debugPrint('Tokens refreshed');
      Map<String, dynamic> responseBody = await jsonDecode(response.body);
      String accessToken = responseBody['access'] as String;
      String refreshToken = responseBody['refresh'] as String;

      // Store new tokens
      await _storage.saveTokens(accessToken, refreshToken);

      return {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      };
    } else {
      // Tokens invalid
      debugPrint(response.body);
      debugPrint('Tokens invalid. Not refreshed.');

      // Delete tokens
      await _storage.deleteTokens();

      return null;
    }
  }

  static Future<bool> logout() async {
    // Get tokens from storage
    Map<String, String>? tokens = await getTokens();
    if (tokens == null) {
      return false;
    }

    http.Response response = await http.post(
      Uri.parse('$serverUrl/auth/logout'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Bearer ${tokens['accessToken']}',
      },
      body: jsonEncode(<String, String?>{
        'refresh': tokens['refreshToken'],
      }),
    );

    debugPrint(response.body);

    return response.statusCode == 204;
  }

  static Future<Map<String, dynamic>?> totpRegister(
      String tempAccessToken) async {
    http.Response response = await http.post(
      Uri.parse('$serverUrl/auth/totp/register'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Bearer $tempAccessToken',
      },
    );

    if (response.statusCode == 200) {
      Map<String, dynamic> responseBody = jsonDecode(response.body);

      String qrCode = responseBody['barcode'] as String;
      String otpauthUrl = responseBody['url'] as String;
      debugPrint('QR Code: $qrCode');
      debugPrint('OTPAuth URL: $otpauthUrl');

      return {
        'hasGeneratedQrCode': true,
        'qrCode': qrCode,
        'otpauthUrl': otpauthUrl,
      };
    } else {
      debugPrint(response.body);
      return null;
    }
  }

  static Future<bool> totpLogin(
    String tempAccessToken,
    String totpCode,
  ) async {
    http.Response response = await http.post(
      Uri.parse('$serverUrl/auth/totp'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Bearer $tempAccessToken',
      },
      body: jsonEncode(<String, String>{
        'totp': totpCode,
      }),
    );

    if (response.statusCode == 200) {
      Map<String, dynamic> responseBody = jsonDecode(response.body);

      String accessToken = responseBody['access'] as String;
      String refreshToken = responseBody['refresh'] as String;
      debugPrint('Access token: $accessToken');
      debugPrint('Refresh token: $refreshToken');

      // Save access token to shared preferences
      _storage.saveTokens(accessToken, refreshToken);

      return true;
    } else {
      debugPrint(response.body);
      return false;
    }
  }
}