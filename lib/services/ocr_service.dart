import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class OcrService {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _recognizer = TextRecognizer();

  Future<Map<String, dynamic>?> scanReceipt() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) return null;

    final inputImage = InputImage.fromFile(File(image.path));
    final RecognizedText recognizedText = await _recognizer.processImage(
      inputImage,
    );

    String text = '';
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        text += line.text + '\n';
      }
    }

    double? totalAmount;
    double? liters;
    DateTime? receiptDate;

    // Ищем сумму (ИТОГ, Итого, TOTAL)
    final totalRegex = RegExp(
      r'(?:ИТОГ|Итого|TOTAL|ИТОГО)[^\d]*(\d+[.,]\d+)',
      caseSensitive: false,
    );
    final totalMatch = totalRegex.firstMatch(text);
    if (totalMatch != null) {
      totalAmount = double.tryParse(totalMatch.group(1)!.replaceAll(',', '.'));
    }

    // Ищем литраж (число перед "л", "литр", "л.")
    final litersRegex = RegExp(
      r'(\d+[.,]\d+)\s*(?:л|литр|л\.)',
      caseSensitive: false,
    );
    final litersMatch = litersRegex.firstMatch(text);
    if (litersMatch != null) {
      liters = double.tryParse(litersMatch.group(1)!.replaceAll(',', '.'));
    }

    // Ищем дату в формате ДД.ММ.ГГГГ или ДД/ММ/ГГГГ
    final dateRegex = RegExp(r'(\d{2})[./](\d{2})[./](\d{4})');
    final dateMatch = dateRegex.firstMatch(text);
    if (dateMatch != null) {
      final day = int.tryParse(dateMatch.group(1)!);
      final month = int.tryParse(dateMatch.group(2)!);
      final year = int.tryParse(dateMatch.group(3)!);
      if (day != null && month != null && year != null) {
        try {
          receiptDate = DateTime(year, month, day);
        } catch (_) {}
      }
    }

    // Если сумму не нашли по ключевым словам, берем самое большое число в чеке
    if (totalAmount == null) {
      final numbers = RegExp(r'\d+[.,]\d+').allMatches(text);
      double maxNum = 0;
      for (var match in numbers) {
        final num = double.tryParse(match.group(0)!.replaceAll(',', '.')) ?? 0;
        if (num > maxNum) maxNum = num;
      }
      if (maxNum > 0) totalAmount = maxNum;
    }

    return {'amount': totalAmount, 'liters': liters, 'date': receiptDate};
  }

  void dispose() {
    _recognizer.close();
  }

  Future<String?> uploadToCloudinary(Uint8List imageBytes) async {
    const cloudName = 'a9m580vg';
    const uploadPreset = 'autodiary_upload';

    final url = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );

    try {
      final request = http.MultipartRequest('POST', url);
      request.fields['upload_preset'] = uploadPreset;
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'receipt.jpg',
        ),
      );

      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonMap = jsonDecode(responseData);
        return jsonMap['secure_url'] as String?;
      } else {
        debugPrint('Cloudinary error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Cloudinary upload failed: $e');
      return null;
    }
  }
}
