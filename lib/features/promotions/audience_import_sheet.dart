import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZLibDecoder;
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../data/services/vennuzo_creative_services_service.dart';
import '../../domain/models/account_models.dart';

Future<AudienceImportResult?> showAudienceImportSheet(BuildContext context) {
  return showModalBottomSheet<AudienceImportResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AudienceImportSheet(),
  );
}

class _AudienceImportSheet extends StatefulWidget {
  const _AudienceImportSheet();

  @override
  State<_AudienceImportSheet> createState() => _AudienceImportSheetState();
}

class _AudienceImportSheetState extends State<_AudienceImportSheet> {
  final _sourceController = TextEditingController(text: 'App audience import');
  final _tagsController = TextEditingController();
  final _contactsController = TextEditingController();
  bool _submitting = false;
  bool _readingFile = false;
  bool _markAllConsented = false;
  bool _consentConfirmed = false;
  String _duplicateMode = 'merge';
  String _fileStatus = '';

  @override
  void dispose() {
    _sourceController.dispose();
    _tagsController.dispose();
    _contactsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: VennuzoTheme.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VennuzoTheme.radiusXl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, viewInsets.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close audience import',
                ),
              ),
              Text('Import owned audience', style: context.text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Paste contacts or upload CSV, TSV, TXT, Excel, or text-based PDF files.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _sourceController,
                decoration: const InputDecoration(labelText: 'Source name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'List tags',
                  hintText: 'VIP, sponsors, December leads',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _readingFile || _submitting
                          ? null
                          : _pickContactFile,
                      icon: const Icon(Icons.attach_file_rounded),
                      label: Text(
                        _readingFile ? 'Reading file…' : 'Upload contact file',
                      ),
                    ),
                  ),
                ],
              ),
              if (_fileStatus.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_fileStatus, style: context.text.bodySmall),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _contactsController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    labelText: 'Contacts',
                    hintText:
                        'Ama Mensah, 0241234567, ama@email.com\nKwame, 0555555555',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _duplicateMode,
                decoration: const InputDecoration(labelText: 'Duplicates'),
                items: const [
                  DropdownMenuItem(
                    value: 'merge',
                    child: Text('Merge tags and source'),
                  ),
                  DropdownMenuItem(
                    value: 'update',
                    child: Text('Update existing contact'),
                  ),
                  DropdownMenuItem(
                    value: 'skip',
                    child: Text('Skip existing contact'),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) =>
                          setState(() => _duplicateMode = value ?? 'merge'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _markAllConsented,
                onChanged: _submitting
                    ? null
                    : (value) =>
                          setState(() => _markAllConsented = value ?? false),
                title: const Text('Mark all pasted/uploaded rows as consented'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consentConfirmed,
                onChanged: _submitting
                    ? null
                    : (value) =>
                          setState(() => _consentConfirmed = value ?? false),
                title: const Text(
                  'I confirm these contacts gave marketing/SMS consent.',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.upload_rounded),
                  label: Text(_submitting ? 'Importing…' : 'Import contacts'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final session = context.read<VennuzoSessionController>();
    final organizationId = _organizationIdFor(session.viewer);
    if (organizationId == null) {
      _showMessage('Open an organizer workspace first.');
      return;
    }
    final contacts = _parseContacts(_contactsController.text);
    if (contacts.isEmpty) {
      _showMessage('Paste at least one contact.');
      return;
    }
    if (!_consentConfirmed) {
      _showMessage('Confirm contact consent before importing.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final result =
          await VennuzoCreativeServicesService.importAudienceContacts(
            organizationId: organizationId,
            sourceName: _sourceController.text.trim().isEmpty
                ? 'App audience import'
                : _sourceController.text.trim(),
            contacts: contacts,
            duplicateMode: _duplicateMode,
          );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      _showMessage(
        error.toString().contains('permission-denied')
            ? 'Audience import is not enabled for this workspace yet.'
            : error.toString(),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickContactFile() async {
    setState(() {
      _readingFile = true;
      _fileStatus =
          'Choose a CSV, TSV, TXT, XLS, XLSX, or text-based PDF file.';
    });
    try {
      final result = await file_picker.FilePicker.pickFiles(
        type: file_picker.FileType.custom,
        allowedExtensions: const ['csv', 'tsv', 'txt', 'xls', 'xlsx', 'pdf'],
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) {
        setState(() => _fileStatus = '');
        return;
      }
      final text = _textFromPickedFile(file.name, bytes);
      if (text.trim().isEmpty) {
        final lower = file.name.toLowerCase();
        setState(
          () => _fileStatus = lower.endsWith('.pdf')
              ? 'No readable contact text found. Image-only or scanned PDFs are not supported in mobile import.'
              : 'No readable contact text found.',
        );
        return;
      }
      _contactsController.text = text;
      if (_sourceController.text.trim() == 'App audience import') {
        _sourceController.text = file.name.replaceFirst(
          RegExp(r'\.[^.]+$'),
          '',
        );
      }
      final count = _parseContacts(text).length;
      setState(
        () => _fileStatus = count == 0
            ? 'File was readable, but no phone numbers or emails were found in ${file.name}.'
            : 'Prepared $count contact${count == 1 ? '' : 's'} from ${file.name}.',
      );
    } catch (error) {
      setState(() => _fileStatus = 'Could not read that file: $error');
    } finally {
      if (mounted) setState(() => _readingFile = false);
    }
  }

  String _textFromPickedFile(String name, Uint8List bytes) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      final tableName = decoder.tables.keys.isEmpty
          ? null
          : decoder.tables.keys.first;
      final rows = tableName == null
          ? const <List<dynamic>>[]
          : decoder.tables[tableName]!.rows;
      return rows
          .map((row) => row.map((cell) => '${cell ?? ''}').join(','))
          .join('\n');
    }
    if (lower.endsWith('.pdf')) {
      return _textFromPdf(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _textFromPdf(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final chunks = <String>[];

    chunks.add(_decodePdfContentText(raw));

    final streamPattern = RegExp(
      r'<<(?:.|\n|\r)*?>>\s*stream\r?\n([\s\S]*?)\r?\nendstream',
      multiLine: true,
    );
    for (final match in streamPattern.allMatches(raw)) {
      final objectText = match.group(0) ?? '';
      if (!objectText.contains('FlateDecode')) {
        continue;
      }
      final encodedStream = match.group(1);
      if (encodedStream == null || encodedStream.isEmpty) {
        continue;
      }
      try {
        final streamBytes = Uint8List.fromList(latin1.encode(encodedStream));
        final inflated = ZLibDecoder().decodeBytes(streamBytes);
        chunks.add(
          _decodePdfContentText(latin1.decode(inflated, allowInvalid: true)),
        );
      } catch (_) {
        // Some PDFs use predictors, encryption, or filters this lightweight
        // mobile importer cannot decode. Those should fail as unreadable text.
      }
    }

    return chunks
        .where((chunk) => chunk.trim().isNotEmpty)
        .join('\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _decodePdfContentText(String content) {
    final textBlocks = RegExp(r'BT([\s\S]*?)ET').allMatches(content).toList();
    final target = textBlocks.isEmpty
        ? content
        : textBlocks.map((match) => match.group(1) ?? '').join('\n');
    final parts = <String>[];

    final literalPattern = RegExp(r'\((?:\\.|[^\\)])*\)');
    for (final match in literalPattern.allMatches(target)) {
      parts.add(_decodePdfLiteral(match.group(0)!));
    }

    final hexPattern = RegExp(r'<([0-9A-Fa-f\s]{4,})>');
    for (final match in hexPattern.allMatches(target)) {
      parts.add(_decodePdfHexText(match.group(1)!));
    }

    return parts
        .map((part) => part.replaceAll('\u0000', '').trim())
        .where((part) => part.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _decodePdfLiteral(String token) {
    final body = token.substring(1, token.length - 1);
    final buffer = StringBuffer();
    for (var index = 0; index < body.length; index++) {
      final code = body.codeUnitAt(index);
      if (code != 0x5C || index == body.length - 1) {
        buffer.writeCharCode(code);
        continue;
      }

      final next = body.codeUnitAt(++index);
      switch (next) {
        case 0x6E:
          buffer.write('\n');
        case 0x72:
          buffer.write('\r');
        case 0x74:
          buffer.write('\t');
        case 0x62:
          buffer.write('\b');
        case 0x66:
          buffer.write('\f');
        case 0x28:
        case 0x29:
        case 0x5C:
          buffer.writeCharCode(next);
        case 0x0A:
          break;
        case 0x0D:
          if (index + 1 < body.length && body.codeUnitAt(index + 1) == 0x0A) {
            index++;
          }
        default:
          if (_isOctalDigit(next)) {
            var octal = String.fromCharCode(next);
            while (octal.length < 3 &&
                index + 1 < body.length &&
                _isOctalDigit(body.codeUnitAt(index + 1))) {
              octal += String.fromCharCode(body.codeUnitAt(++index));
            }
            buffer.writeCharCode(int.parse(octal, radix: 8));
          } else {
            buffer.writeCharCode(next);
          }
      }
    }
    return buffer.toString();
  }

  String _decodePdfHexText(String token) {
    var cleaned = token.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) {
      return '';
    }
    if (cleaned.length.isOdd) {
      cleaned = '${cleaned}0';
    }
    final bytes = <int>[];
    for (var index = 0; index < cleaned.length; index += 2) {
      bytes.add(int.parse(cleaned.substring(index, index + 2), radix: 16));
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final buffer = StringBuffer();
      for (var index = 2; index + 1 < bytes.length; index += 2) {
        buffer.writeCharCode((bytes[index] << 8) | bytes[index + 1]);
      }
      return buffer.toString();
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  bool _isOctalDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x37;

  List<Map<String, Object?>> _parseContacts(String value) {
    final contacts = <Map<String, Object?>>[];
    final emailPattern = RegExp(r'[\w.+-]+@[\w.-]+\.\w+');
    final phonePattern = RegExp(r'(\+?233|0)?\d{9}');
    for (final line in value.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final email = emailPattern.firstMatch(trimmed)?.group(0) ?? '';
      final phone = phonePattern.firstMatch(trimmed)?.group(0) ?? '';
      var name = trimmed
          .replaceAll(email, '')
          .replaceAll(phone, '')
          .replaceAll(RegExp(r'[,;]+'), ' ')
          .trim();
      if (name.isEmpty) name = email.isNotEmpty ? email : phone;
      contacts.add(<String, Object?>{
        'displayName': name,
        'email': email,
        'phone': phone,
        'marketingConsent': _markAllConsented || _lineHasConsent(trimmed),
        'smsConsent':
            phone.isNotEmpty && (_markAllConsented || _lineHasConsent(trimmed)),
        'tags': _parseTags(_tagsController.text),
      });
    }
    return contacts;
  }

  bool _lineHasConsent(String value) {
    return RegExp(
      r'\b(yes|true|1|opted?\s*in|subscribed|consented)\b',
      caseSensitive: false,
    ).hasMatch(value);
  }

  List<String> _parseTags(String value) {
    return value
        .split(RegExp(r'[,;|]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(12)
        .toList();
  }

  String? _organizationIdFor(VennuzoViewer viewer) {
    final existing = viewer.defaultOrganizationId?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final uid = viewer.uid?.trim();
    if (uid == null || uid.isEmpty) return null;
    return 'org_$uid';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
