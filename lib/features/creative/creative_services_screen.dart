import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/services/vennuzo_creative_services_service.dart';
import '../../data/services/vennuzo_payment_service.dart';
import '../../domain/models/account_models.dart';
import '../../domain/models/creative_service_models.dart';
import '../../widgets/empty_state_card.dart';
import '../account/auth_prompt_sheet.dart';
import '../manage/host_access_screen.dart';

enum _FlyerExportFormat { story, instagramPost }

const _quickAiEditPrompts = <String>[
  'Make the headline bigger and punchier',
  'Make the date and venue easier to read',
  'Switch the accent color to gold',
  'Add more cinematic glow and depth',
];

class CreativeServicesScreen extends StatefulWidget {
  const CreativeServicesScreen({super.key});

  @override
  State<CreativeServicesScreen> createState() => _CreativeServicesScreenState();
}

class _CreativeServicesScreenState extends State<CreativeServicesScreen> {
  final _imagePicker = ImagePicker();
  final _brandNameController = TextEditingController();
  final _brandStyleController = TextEditingController();
  final _brandColorController = TextEditingController(text: '#7dd3fc');
  final _instagramController = TextEditingController();
  final _websiteController = TextEditingController();
  final _eventNameController = TextEditingController();
  final _venueController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  final _performersController = TextEditingController();
  final _creativeBriefController = TextEditingController();
  final _editInstructionController = TextEditingController();
  final _walletAmountController = TextEditingController(text: '100');
  final _walletPhoneController = TextEditingController();
  final _walletEmailController = TextEditingController();
  final _walletNameController = TextEditingController();

  String? _loadedOrganizationId;
  String _logoUrl = '';
  String _uploadedFlyerUrl = '';
  String _uploadedFlyerName = '';
  String _serviceType = 'event_flyer';
  String? _activeJobId;
  String? _activeVideoJobId;
  bool _loading = false;
  bool _savingBrand = false;
  bool _submitting = false;
  bool _uploading = false;
  bool _topUpSubmitting = false;
  String? _error;
  CreativeServicesPricing _pricing = const CreativeServicesPricing();
  WalletBalance _wallet = const WalletBalance();
  final List<_TierDraft> _tiers = <_TierDraft>[
    _TierDraft(
      name: 'VIP Table',
      price: 'GHS 2,500',
      items: '1 premium bottle\n4 mixers\nPriority entry',
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<VennuzoSessionController>();
    final organizationId = _organizationIdFor(session.viewer);
    if (session.viewer.hasOrganizerAccess &&
        organizationId != null &&
        organizationId != _loadedOrganizationId) {
      _loadedOrganizationId = organizationId;
      unawaited(_load(organizationId, session.viewer));
    }
  }

  @override
  void dispose() {
    _brandNameController.dispose();
    _brandStyleController.dispose();
    _brandColorController.dispose();
    _instagramController.dispose();
    _websiteController.dispose();
    _eventNameController.dispose();
    _venueController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _performersController.dispose();
    _creativeBriefController.dispose();
    _editInstructionController.dispose();
    _walletAmountController.dispose();
    _walletPhoneController.dispose();
    _walletEmailController.dispose();
    _walletNameController.dispose();
    for (final tier in _tiers) {
      tier.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final viewer = session.viewer;
    final organizationId = _organizationIdFor(viewer);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Creative services')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        children: [
          _CreativeHero(
            wallet: _wallet,
            pricing: _pricing,
            onLoadWallet: () => _scrollToWalletHint(context),
          ),
          const SizedBox(height: 20),
          if (session.isGuest)
            EmptyStateCard(
              title: 'Sign in to use creative services',
              body:
                  'Flyers, table-package flyers, and wallet-funded campaigns are organizer tools.',
              icon: Icons.lock_outline,
              actionLabel: 'Sign in or create account',
              onAction: () => showAuthPromptSheet(
                context,
                title: 'Continue to creative services',
                body: 'Create or sign into your Vennuzo organizer account.',
              ),
            )
          else if (!viewer.hasOrganizerAccess)
            EmptyStateCard(
              title: 'Set up host access first',
              body: 'Creative services need an organizer workspace and wallet.',
              icon: Icons.storefront_outlined,
              actionLabel: 'Open host setup',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const HostAccessScreen(),
                ),
              ),
            )
          else if (organizationId == null)
            const EmptyStateCard(
              title: 'Workspace unavailable',
              body:
                  'Open your workspace chooser and select an organizer space.',
              icon: Icons.business_outlined,
            )
          else if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator.adaptive(),
              ),
            )
          else ...[
            if (_error != null) ...[
              _NoticeCard(message: _error!, isError: true),
              const SizedBox(height: 16),
            ],
            _WalletCard(
              wallet: _wallet,
              amountController: _walletAmountController,
              nameController: _walletNameController,
              phoneController: _walletPhoneController,
              emailController: _walletEmailController,
              submitting: _topUpSubmitting,
              onTopUp: () => _topUpWallet(organizationId),
              onRefresh: () => _refreshWallet(organizationId),
            ),
            const SizedBox(height: 18),
            _BrandCard(
              logoUrl: _logoUrl,
              saving: _savingBrand,
              uploading: _uploading,
              brandNameController: _brandNameController,
              brandStyleController: _brandStyleController,
              brandColorController: _brandColorController,
              instagramController: _instagramController,
              websiteController: _websiteController,
              onPickLogo: () => _pickLogo(organizationId),
              onSave: () => _saveBrand(organizationId),
            ),
            const SizedBox(height: 18),
            _GeneratorCard(
              serviceType: _serviceType,
              pricing: _pricing,
              eventNameController: _eventNameController,
              venueController: _venueController,
              dateController: _dateController,
              timeController: _timeController,
              performersController: _performersController,
              creativeBriefController: _creativeBriefController,
              tiers: _tiers,
              uploadedFlyerName: _uploadedFlyerName,
              submitting: _submitting,
              uploading: _uploading,
              onServiceTypeChanged: (value) =>
                  setState(() => _serviceType = value),
              onAddTier: () => setState(() => _tiers.add(_TierDraft())),
              onRemoveTier: (tier) => setState(() {
                tier.dispose();
                _tiers.remove(tier);
              }),
              onPickSource: () => _pickSourceImage(organizationId),
              onSubmit: () => _submitGeneration(organizationId),
            ),
            if (_activeJobId != null) ...[
              const SizedBox(height: 18),
              StreamBuilder<CreativeJobSnapshot>(
                stream: VennuzoCreativeServicesService.watchJob(_activeJobId!),
                builder: (context, snapshot) {
                  final job = snapshot.data;
                  return _JobCard(
                    job: job,
                    onOpen: job?.imageUrl.isEmpty ?? true
                        ? null
                        : () => _openUrl(job!.imageUrl),
                    onShare: job?.imageUrl.isEmpty ?? true
                        ? null
                        : () => _shareFlyer(
                            job!.imageUrl,
                            job.eventName,
                            _FlyerExportFormat.story,
                          ),
                    onSharePost: job?.imageUrl.isEmpty ?? true
                        ? null
                        : () => _shareFlyer(
                            job!.imageUrl,
                            job.eventName,
                            _FlyerExportFormat.instagramPost,
                          ),
                  );
                },
              ),
            ],
            if (_activeVideoJobId != null) ...[
              const SizedBox(height: 18),
              StreamBuilder<CreativeVideoJobSnapshot>(
                stream: VennuzoCreativeServicesService.watchVideoJob(
                  _activeVideoJobId!,
                ),
                builder: (context, snapshot) {
                  final job = snapshot.data;
                  return _VideoJobCard(
                    job: job,
                    onOpen: job?.videoUrl.isEmpty ?? true
                        ? null
                        : () => _openUrl(job!.videoUrl),
                    onShare: job?.videoUrl.isEmpty ?? true
                        ? null
                        : () => _shareVideo(job!.videoUrl, job.eventName),
                  );
                },
              ),
            ],
            const SizedBox(height: 18),
            StreamBuilder<List<CreativeSession>>(
              stream: VennuzoCreativeServicesService.watchSessions(
                organizationId,
              ),
              builder: (context, snapshot) {
                final sessions = snapshot.data ?? const <CreativeSession>[];
                return _RecentAssetsCard(
                  sessions: sessions,
                  editController: _editInstructionController,
                  submitting: _submitting,
                  videoPriceGhs: _pricing.flyerVideoGhs,
                  onOpen: _openUrl,
                  onShare: (session) => _shareFlyer(
                    session.imageUrl,
                    session.eventName,
                    _FlyerExportFormat.story,
                  ),
                  onSharePost: (session) => _shareFlyer(
                    session.imageUrl,
                    session.eventName,
                    _FlyerExportFormat.instagramPost,
                  ),
                  onMinorEdit: (session) =>
                      _submitEdit(organizationId, session, 'minor'),
                  onRedesign: (session) =>
                      _submitEdit(organizationId, session, 'redesign'),
                  onAnimate: (session) =>
                      _submitVideoJob(organizationId, session),
                  onOpenVideo: _openUrl,
                  onShareVideo: (session) =>
                      _shareVideo(session.latestVideoUrl, session.eventName),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _load(String organizationId, VennuzoViewer viewer) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await VennuzoCreativeServicesService.getConfig(
        organizationId,
      );
      final wallet = await VennuzoPaymentService.getWalletBalance(
        organizationId: organizationId,
      );
      if (!mounted) return;
      _applyBrand(config.brand);
      setState(() {
        _pricing = config.pricing;
        _wallet = wallet;
        _walletNameController.text = viewer.displayName;
        _walletPhoneController.text = viewer.phone ?? '';
        _walletEmailController.text = viewer.email ?? '';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyBrand(CreativeBrandConfig brand) {
    _brandNameController.text = brand.brandName;
    _brandStyleController.text = brand.brandStyle;
    _brandColorController.text = brand.brandColor;
    _instagramController.text = brand.instagram;
    _websiteController.text = brand.website;
    _logoUrl = brand.logoUrl;
  }

  Future<void> _refreshWallet(String organizationId) async {
    try {
      final wallet = await VennuzoPaymentService.getWalletBalance(
        organizationId: organizationId,
      );
      if (mounted) setState(() => _wallet = wallet);
    } catch (error) {
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _topUpWallet(String organizationId) async {
    final amount = double.tryParse(_walletAmountController.text.trim()) ?? 0;
    if (amount < 1) {
      _showMessage('Enter at least GHS 1 to load your wallet.');
      return;
    }
    final phone = _walletPhoneController.text.trim();
    if (phone.isEmpty || phone.replaceAll(RegExp(r'[^0-9]'), '').length < 9) {
      _showMessage('Enter the mobile money number to charge.');
      return;
    }
    setState(() => _topUpSubmitting = true);
    try {
      await VennuzoPaymentService.startWalletTopUp(
        organizationId: organizationId,
        amount: amount,
        payeeName: _walletNameController.text.trim(),
        payeeMobileNumber: phone,
        payeeEmail: _walletEmailController.text.trim(),
      );
      _showMessage('Hubtel checkout opened. Balance updates after payment.');
    } catch (error) {
      _showMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _topUpSubmitting = false);
    }
  }

  Future<void> _pickLogo(String organizationId) async {
    await _pickAndUpload(
      organizationId: organizationId,
      folder: 'brand',
      onUploaded: (url, name) => setState(() => _logoUrl = url),
    );
  }

  Future<void> _pickSourceImage(String organizationId) async {
    await _pickAndUpload(
      organizationId: organizationId,
      folder: 'source',
      onUploaded: (url, name) => setState(() {
        _uploadedFlyerUrl = url;
        _uploadedFlyerName = name;
      }),
    );
  }

  Future<void> _pickAndUpload({
    required String organizationId,
    required String folder,
    required void Function(String url, String name) onUploaded,
  }) async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (file == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await VennuzoCreativeServicesService.uploadAsset(
        organizationId: organizationId,
        file: file,
        folder: folder,
      );
      onUploaded(url, file.name);
    } catch (error) {
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _saveBrand(String organizationId) async {
    setState(() => _savingBrand = true);
    try {
      final brand = await VennuzoCreativeServicesService.saveBrand(
        organizationId: organizationId,
        brand: CreativeBrandConfig(
          brandName: _brandNameController.text,
          brandStyle: _brandStyleController.text,
          brandColor: _brandColorController.text,
          logoUrl: _logoUrl,
          instagram: _instagramController.text,
          website: _websiteController.text,
        ),
      );
      if (mounted) {
        _applyBrand(brand);
        _showMessage('Brand saved.');
      }
    } catch (error) {
      _showMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _savingBrand = false);
    }
  }

  Future<void> _submitGeneration(String organizationId) async {
    if (_eventNameController.text.trim().isEmpty) {
      _showMessage('Enter an event name first.');
      return;
    }
    final tiers = _tiers
        .map((tier) => tier.toCreativeTier())
        .where((tier) => tier.name.trim().isNotEmpty)
        .toList();
    if (_serviceType == 'table_package_flyer' && tiers.isEmpty) {
      _showMessage('Add at least one table package tier.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _activeJobId = null;
    });
    try {
      final result = await VennuzoCreativeServicesService.submitJob(
        organizationId: organizationId,
        serviceType: _serviceType,
        eventName: _eventNameController.text.trim(),
        venue: _venueController.text.trim(),
        date: _dateController.text.trim(),
        time: _timeController.text.trim(),
        performers: _performersController.text.trim(),
        creativeDescription: _creativeBriefController.text.trim(),
        uploadedFlyerUrl: _uploadedFlyerUrl,
        tiers: tiers,
      );
      setState(() => _activeJobId = result.jobId);
      _showMessage(
        result.priceChargedGhs > 0
            ? 'Generation started. Wallet charged ${formatMoney(result.priceChargedGhs)}.'
            : 'Generation started using included quota.',
      );
      unawaited(_refreshWallet(organizationId));
    } catch (error) {
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitEdit(
    String organizationId,
    CreativeSession source,
    String editMode,
  ) async {
    final instruction = _editInstructionController.text.trim();
    if (instruction.isEmpty) {
      _showMessage('Describe the edit first.');
      return;
    }
    setState(() {
      _submitting = true;
      _activeJobId = null;
    });
    try {
      final result = await VennuzoCreativeServicesService.submitEdit(
        organizationId: organizationId,
        source: source,
        editMode: editMode,
        instruction: instruction,
      );
      setState(() => _activeJobId = result.jobId);
      _showMessage(
        result.quotaCovered
            ? 'Included ${editMode == 'minor' ? 'edit' : 'redesign'} queued.'
            : 'Queued as a paid redesign.',
      );
      unawaited(_refreshWallet(organizationId));
    } catch (error) {
      _showMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitVideoJob(
    String organizationId,
    CreativeSession source,
  ) async {
    setState(() {
      _submitting = true;
      _activeVideoJobId = null;
    });
    try {
      final result = await VennuzoCreativeServicesService.submitVideoJob(
        organizationId: organizationId,
        source: source,
      );
      setState(() => _activeVideoJobId = result.jobId);
      _showMessage(
        'Flyer animation started. Wallet charged ${formatMoney(result.priceChargedGhs)}.',
      );
      unawaited(_refreshWallet(organizationId));
    } catch (error) {
      _showMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _organizationIdFor(VennuzoViewer viewer) {
    final existing = viewer.defaultOrganizationId?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final uid = viewer.uid?.trim();
    if (uid == null || uid.isEmpty) return null;
    return 'org_$uid';
  }

  void _scrollToWalletHint(BuildContext context) {
    _showMessage('Use the Services wallet card below to top up with Hubtel.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _shareFlyer(
    String imageUrl,
    String eventName,
    _FlyerExportFormat format,
  ) async {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null) {
      _showMessage('Flyer link is unavailable.');
      return;
    }
    try {
      _showMessage(
        format == _FlyerExportFormat.instagramPost
            ? 'Preparing Instagram post...'
            : 'Preparing flyer...',
      );
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Could not download flyer (${response.statusCode}).');
      }
      final sourceContentType =
          response.headers['content-type'] ?? 'image/jpeg';
      final bytes = format == _FlyerExportFormat.instagramPost
          ? await _buildInstagramPostBytes(response.bodyBytes)
          : response.bodyBytes;
      final contentType = format == _FlyerExportFormat.instagramPost
          ? 'image/png'
          : sourceContentType;
      final extension = contentType.contains('png') ? 'png' : 'jpg';
      final suffix = format == _FlyerExportFormat.instagramPost
          ? 'instagram-post'
          : 'story';
      final fileName =
          '${_safeFileName(eventName, fallback: 'vennuzo-flyer')}-$suffix.$extension';
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: contentType, name: fileName)],
          fileNameOverrides: [fileName],
          text: eventName.isEmpty
              ? 'Vennuzo flyer'
              : '$eventName ${format == _FlyerExportFormat.instagramPost ? 'Instagram post' : 'Instagram story'}',
          title: format == _FlyerExportFormat.instagramPost
              ? 'Vennuzo Instagram post'
              : 'Vennuzo flyer',
        ),
      );
    } catch (error) {
      _showMessage('Could not prepare flyer: ${_friendlyError(error)}');
    }
  }

  Future<void> _shareVideo(String videoUrl, String eventName) async {
    final uri = Uri.tryParse(videoUrl);
    if (uri == null) {
      _showMessage('Video link is unavailable.');
      return;
    }
    try {
      _showMessage('Preparing video...');
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Could not download video (${response.statusCode}).');
      }
      final fileName =
          '${_safeFileName(eventName, fallback: 'vennuzo-flyer')}-video.mp4';
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'video/mp4', name: fileName)],
          fileNameOverrides: [fileName],
          text: eventName.isEmpty ? 'Vennuzo flyer video' : '$eventName video',
          title: 'Vennuzo flyer video',
        ),
      );
    } catch (error) {
      _showMessage('Could not prepare video: ${_friendlyError(error)}');
    }
  }

  Future<Uint8List> _buildInstagramPostBytes(Uint8List sourceBytes) async {
    final source = await _decodeImage(sourceBytes);
    const postSize = 1080.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, postSize, postSize),
    );
    final sourceRect = Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      source.height.toDouble(),
    );

    final coverScale = math.max(
      postSize / source.width,
      postSize / source.height,
    );
    final coverSize = Size(
      source.width * coverScale,
      source.height * coverScale,
    );
    final coverRect = Rect.fromLTWH(
      (postSize - coverSize.width) / 2,
      (postSize - coverSize.height) / 2,
      coverSize.width,
      coverSize.height,
    );
    canvas.drawImageRect(
      source,
      sourceRect,
      coverRect,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, postSize, postSize),
      Paint()..color = Colors.black.withValues(alpha: 0.34),
    );

    final containScale = math.min(
      postSize / source.width,
      postSize / source.height,
    );
    final storySize = Size(
      source.width * containScale,
      source.height * containScale,
    );
    final storyRect = Rect.fromLTWH(
      (postSize - storySize.width) / 2,
      (postSize - storySize.height) / 2,
      storySize.width,
      storySize.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(storyRect.inflate(10), const Radius.circular(28)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.48)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawImageRect(source, sourceRect, storyRect, Paint());

    final picture = recorder.endRecording();
    final image = await picture.toImage(postSize.toInt(), postSize.toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    source.dispose();
    image.dispose();
    picture.dispose();
    if (png == null) {
      throw Exception('Could not render Instagram post image.');
    }
    return png.buffer.asUint8List();
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  String _safeFileName(String value, {required String fallback}) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? fallback : normalized;
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.contains('failed-precondition') ||
        text.toLowerCase().contains('insufficient wallet')) {
      return 'Insufficient wallet balance. Load your services wallet before buying push, SMS, flyers, table-package flyers, or flyer videos.';
    }
    if (text.contains('permission-denied')) {
      return 'This workspace needs the right plan or organizer permission for this service.';
    }
    return text;
  }
}

class _CreativeHero extends StatelessWidget {
  const _CreativeHero({
    required this.wallet,
    required this.pricing,
    required this.onLoadWallet,
  });

  final WalletBalance wallet;
  final CreativeServicesPricing pricing;
  final VoidCallback onLoadWallet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        gradient: VennuzoTheme.brandGradient,
        boxShadow: VennuzoTheme.shadowElevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Creative services',
            style: context.text.labelLarge?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Generate premium flyers and table-package flyers.',
            style: context.text.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroPill(label: '${formatMoney(pricing.flyerGhs)} flyer'),
              _HeroPill(
                label:
                    '${formatMoney(pricing.tablePackageFlyerGhs)} table flyer',
              ),
              _HeroPill(
                label: '${formatMoney(pricing.flyerVideoGhs)} flyer video',
              ),
              _HeroPill(
                label:
                    '${pricing.includedMinorEdits} edits · ${pricing.includedRedesigns} redesigns',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width - 100,
                ),
                child: Text(
                  'Wallet ${formatMoney(wallet.availableBalance)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onLoadWallet,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Load'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message, this.isError = false});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isError ? VennuzoTheme.primaryEnd : VennuzoTheme.primaryStart)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
        border: Border.all(
          color: (isError ? VennuzoTheme.primaryEnd : VennuzoTheme.primaryStart)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Text(message, style: context.text.bodyMedium),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.wallet,
    required this.amountController,
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.submitting,
    required this.onTopUp,
    required this.onRefresh,
  });

  final WalletBalance wallet;
  final TextEditingController amountController;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final bool submitting;
  final VoidCallback onTopUp;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      eyebrow: 'Services wallet',
      title: 'Pay for push, SMS, flyers, and flyer videos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                label: 'Available',
                value: formatMoney(wallet.availableBalance),
              ),
              _MetricChip(
                label: 'Held',
                value: formatMoney(wallet.heldBalance),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Top-up amount'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Payee name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Mobile money phone'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email optional'),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: submitting ? null : onTopUp,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text(submitting ? 'Opening Hubtel…' : 'Load wallet'),
              ),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrandCard extends StatelessWidget {
  const _BrandCard({
    required this.logoUrl,
    required this.saving,
    required this.uploading,
    required this.brandNameController,
    required this.brandStyleController,
    required this.brandColorController,
    required this.instagramController,
    required this.websiteController,
    required this.onPickLogo,
    required this.onSave,
  });

  final String logoUrl;
  final bool saving;
  final bool uploading;
  final TextEditingController brandNameController;
  final TextEditingController brandStyleController;
  final TextEditingController brandColorController;
  final TextEditingController instagramController;
  final TextEditingController websiteController;
  final VoidCallback onPickLogo;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      eyebrow: 'Brand profile',
      title: 'Your flyer brand',
      child: Column(
        children: [
          TextField(
            controller: brandNameController,
            decoration: const InputDecoration(labelText: 'Brand name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: brandColorController,
            decoration: const InputDecoration(labelText: 'Brand color'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: brandStyleController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Brand style'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: instagramController,
            decoration: const InputDecoration(labelText: 'Instagram'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: websiteController,
            decoration: const InputDecoration(labelText: 'Website'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: VennuzoTheme.surfaceElevated,
                  border: Border.all(color: VennuzoTheme.borderBright),
                ),
                clipBehavior: Clip.antiAlias,
                child: logoUrl.isEmpty
                    ? const Icon(Icons.image_outlined)
                    : _NetworkFlyerImage(url: logoUrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: uploading ? null : onPickLogo,
                  icon: const Icon(Icons.upload_rounded),
                  label: Text(uploading ? 'Uploading…' : 'Upload logo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: saving ? null : onSave,
              icon: const Icon(Icons.save_outlined),
              label: Text(saving ? 'Saving…' : 'Save brand'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneratorCard extends StatelessWidget {
  const _GeneratorCard({
    required this.serviceType,
    required this.pricing,
    required this.eventNameController,
    required this.venueController,
    required this.dateController,
    required this.timeController,
    required this.performersController,
    required this.creativeBriefController,
    required this.tiers,
    required this.uploadedFlyerName,
    required this.submitting,
    required this.uploading,
    required this.onServiceTypeChanged,
    required this.onAddTier,
    required this.onRemoveTier,
    required this.onPickSource,
    required this.onSubmit,
  });

  final String serviceType;
  final CreativeServicesPricing pricing;
  final TextEditingController eventNameController;
  final TextEditingController venueController;
  final TextEditingController dateController;
  final TextEditingController timeController;
  final TextEditingController performersController;
  final TextEditingController creativeBriefController;
  final List<_TierDraft> tiers;
  final String uploadedFlyerName;
  final bool submitting;
  final bool uploading;
  final ValueChanged<String> onServiceTypeChanged;
  final VoidCallback onAddTier;
  final ValueChanged<_TierDraft> onRemoveTier;
  final VoidCallback onPickSource;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final price = serviceType == 'table_package_flyer'
        ? pricing.tablePackageFlyerGhs
        : pricing.flyerGhs;
    return _SectionCard(
      eyebrow: 'Generator',
      title: serviceType == 'table_package_flyer'
          ? 'Table package flyer'
          : 'Event flyer',
      child: Column(
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'event_flyer',
                label: Text('Event'),
                icon: Icon(Icons.auto_awesome_outlined),
              ),
              ButtonSegment(
                value: 'table_package_flyer',
                label: Text('Tables'),
                icon: Icon(Icons.table_bar_outlined),
              ),
            ],
            selected: {serviceType},
            onSelectionChanged: (value) => onServiceTypeChanged(value.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: eventNameController,
            decoration: const InputDecoration(labelText: 'Event name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: venueController,
            decoration: const InputDecoration(labelText: 'Venue'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: dateController,
                  decoration: const InputDecoration(labelText: 'Date'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: timeController,
                  decoration: const InputDecoration(labelText: 'Time'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: performersController,
            decoration: const InputDecoration(labelText: 'DJs / performers'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: creativeBriefController,
            minLines: 4,
            maxLines: 7,
            decoration: const InputDecoration(labelText: 'Creative direction'),
          ),
          if (serviceType == 'table_package_flyer') ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Table tiers', style: context.text.titleMedium),
            ),
            const SizedBox(height: 8),
            for (final tier in tiers)
              _TierEditor(
                tier: tier,
                removable: tiers.length > 1,
                onRemove: () => onRemoveTier(tier),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddTier,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add tier'),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width - 120,
                ),
                child: Text(
                  uploadedFlyerName.isEmpty
                      ? 'Optional source image'
                      : uploadedFlyerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              OutlinedButton.icon(
                onPressed: uploading ? null : onPickSource,
                icon: const Icon(Icons.image_outlined),
                label: Text(uploading ? 'Uploading…' : 'Upload'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: Text(
                submitting ? 'Starting…' : 'Generate for ${formatMoney(price)}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TierEditor extends StatelessWidget {
  const _TierEditor({
    required this.tier,
    required this.removable,
    required this.onRemove,
  });

  final _TierDraft tier;
  final bool removable;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VennuzoTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: VennuzoTheme.borderBright),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: tier.nameController,
                  decoration: const InputDecoration(labelText: 'Tier name'),
                ),
              ),
              if (removable)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: tier.priceController,
            decoration: const InputDecoration(labelText: 'Price'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: tier.itemsController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Items included',
              hintText: 'One item per line',
            ),
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.onOpen,
    required this.onShare,
    required this.onSharePost,
  });

  final CreativeJobSnapshot? job;
  final VoidCallback? onOpen;
  final VoidCallback? onShare;
  final VoidCallback? onSharePost;

  @override
  Widget build(BuildContext context) {
    final progress = ((job?.progress ?? 0).clamp(0, 100)) / 100;
    return _SectionCard(
      eyebrow: 'Current job',
      title: job?.currentStep.isNotEmpty == true ? job!.currentStep : 'Queued',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress == 0 ? null : progress),
          const SizedBox(height: 12),
          Text('Status: ${job?.status ?? 'pending'}'),
          if (job?.error.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(job!.error, style: TextStyle(color: VennuzoTheme.primaryEnd)),
          ],
          if (job?.imageUrl.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: _NetworkFlyerImage(url: job!.imageUrl),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open flyer'),
                ),
                FilledButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Download story'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onSharePost,
                  icon: const Icon(Icons.crop_square_rounded),
                  label: const Text('Download IG post'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VideoJobCard extends StatelessWidget {
  const _VideoJobCard({
    required this.job,
    required this.onOpen,
    required this.onShare,
  });

  final CreativeVideoJobSnapshot? job;
  final VoidCallback? onOpen;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final progress = ((job?.progress ?? 0).clamp(0, 100)) / 100;
    return _SectionCard(
      eyebrow: 'Flyer video',
      title: job?.currentStep.isNotEmpty == true ? job!.currentStep : 'Queued',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress == 0 ? null : progress),
          const SizedBox(height: 12),
          Text('Status: ${job?.status ?? 'pending'}'),
          if (job?.motionPrompt.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(job!.motionPrompt, style: context.text.bodySmall),
          ],
          if (job?.error.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(job!.error, style: TextStyle(color: VennuzoTheme.primaryEnd)),
          ],
          if (job?.videoUrl.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: const Text('Open video'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Download video'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentAssetsCard extends StatelessWidget {
  const _RecentAssetsCard({
    required this.sessions,
    required this.editController,
    required this.submitting,
    required this.videoPriceGhs,
    required this.onOpen,
    required this.onShare,
    required this.onSharePost,
    required this.onMinorEdit,
    required this.onRedesign,
    required this.onAnimate,
    required this.onOpenVideo,
    required this.onShareVideo,
  });

  final List<CreativeSession> sessions;
  final TextEditingController editController;
  final bool submitting;
  final double videoPriceGhs;
  final ValueChanged<String> onOpen;
  final ValueChanged<CreativeSession> onShare;
  final ValueChanged<CreativeSession> onSharePost;
  final ValueChanged<CreativeSession> onMinorEdit;
  final ValueChanged<CreativeSession> onRedesign;
  final ValueChanged<CreativeSession> onAnimate;
  final ValueChanged<String> onOpenVideo;
  final ValueChanged<CreativeSession> onShareVideo;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      eyebrow: 'Projects',
      title: 'Recent creative assets',
      child: sessions.isEmpty
          ? const Text('No flyers yet. Generate your first paid flyer above.')
          : Column(
              children: [
                TextField(
                  controller: editController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'AI minor edit instruction',
                    hintText:
                        'Make the date larger, change the accent color...',
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final prompt in _quickAiEditPrompts)
                        ActionChip(
                          label: Text(prompt),
                          onPressed: submitting
                              ? null
                              : () {
                                  editController.text = prompt;
                                  editController.selection =
                                      TextSelection.collapsed(
                                        offset: editController.text.length,
                                      );
                                },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final session in sessions)
                  _SessionTile(
                    session: session,
                    submitting: submitting,
                    videoPriceGhs: videoPriceGhs,
                    onOpen: () => onOpen(session.imageUrl),
                    onShare: () => onShare(session),
                    onSharePost: () => onSharePost(session),
                    onMinorEdit: () => onMinorEdit(session),
                    onRedesign: () => onRedesign(session),
                    onAnimate: () => onAnimate(session),
                    onOpenVideo: session.latestVideoUrl.isEmpty
                        ? null
                        : () => onOpenVideo(session.latestVideoUrl),
                    onShareVideo: session.latestVideoUrl.isEmpty
                        ? null
                        : () => onShareVideo(session),
                  ),
              ],
            ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.submitting,
    required this.videoPriceGhs,
    required this.onOpen,
    required this.onShare,
    required this.onSharePost,
    required this.onMinorEdit,
    required this.onRedesign,
    required this.onAnimate,
    required this.onOpenVideo,
    required this.onShareVideo,
  });

  final CreativeSession session;
  final bool submitting;
  final double videoPriceGhs;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onSharePost;
  final VoidCallback onMinorEdit;
  final VoidCallback onRedesign;
  final VoidCallback onAnimate;
  final VoidCallback? onOpenVideo;
  final VoidCallback? onShareVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VennuzoTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: VennuzoTheme.borderBright),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _NetworkFlyerImage(
              url: session.imageUrl,
              width: 58,
              height: 82,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.eventName, style: context.text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  session.isTablePackage
                      ? 'Table package flyer'
                      : 'Event flyer',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricChip(
                      label: 'Edits',
                      value: '${session.minorEditsRemaining ?? 0}',
                    ),
                    _MetricChip(
                      label: 'Redesigns',
                      value: '${session.redesignsRemaining ?? 0}',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: onOpen,
                      child: const Text('Open'),
                    ),
                    FilledButton.icon(
                      onPressed: onShare,
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Download story'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: onSharePost,
                      icon: const Icon(Icons.crop_square_rounded, size: 18),
                      label: const Text('Download IG post'),
                    ),
                    OutlinedButton(
                      onPressed: submitting ? null : onMinorEdit,
                      child: const Text('AI minor edit'),
                    ),
                    OutlinedButton(
                      onPressed: submitting ? null : onRedesign,
                      child: const Text('Redesign'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: submitting ? null : onAnimate,
                      icon: const Icon(Icons.movie_creation_outlined, size: 18),
                      label: Text('Animate ${formatMoney(videoPriceGhs)}'),
                    ),
                    if (session.latestVideoUrl.isNotEmpty) ...[
                      OutlinedButton.icon(
                        onPressed: onOpenVideo,
                        icon: const Icon(
                          Icons.play_circle_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Open video'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: onShareVideo,
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('Download video'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.eyebrow,
    required this.title,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: VennuzoTheme.surface,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
        border: Border.all(color: VennuzoTheme.borderBright),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: context.text.labelMedium?.copyWith(
              color: VennuzoTheme.textSecondary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(title, style: context.text.titleLarge),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _NetworkFlyerImage extends StatelessWidget {
  const _NetworkFlyerImage({required this.url, this.width, this.height});

  final String url;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) => SizedBox(
        width: width,
        height: height,
        child: const ColoredBox(
          color: VennuzoTheme.surfaceElevated,
          child: Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VennuzoTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: VennuzoTheme.borderBright),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text('$label $value', style: context.text.bodySmall),
      ),
    );
  }
}

class _TierDraft {
  _TierDraft({String name = '', String price = '', String items = ''})
    : nameController = TextEditingController(text: name),
      priceController = TextEditingController(text: price),
      itemsController = TextEditingController(text: items);

  final TextEditingController nameController;
  final TextEditingController priceController;
  final TextEditingController itemsController;

  CreativeTier toCreativeTier() {
    return CreativeTier(
      name: nameController.text.trim(),
      price: priceController.text.trim(),
      items: itemsController.text
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
    );
  }

  void dispose() {
    nameController.dispose();
    priceController.dispose();
    itemsController.dispose();
  }
}
