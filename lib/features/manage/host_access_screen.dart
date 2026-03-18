import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/services/eventora_organizer_application_service.dart';
import '../../domain/models/account_models.dart';
import '../account/sign_in_screen.dart';
import '../account/sign_up_screen.dart';

class HostAccessScreen extends StatefulWidget {
  const HostAccessScreen({super.key});

  @override
  State<HostAccessScreen> createState() => _HostAccessScreenState();
}

class _HostAccessScreenState extends State<HostAccessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  late final TextEditingController _organizerNameController;
  late final TextEditingController _contactPersonController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _businessTypeController;
  late final TextEditingController _businessAddressController;
  late final TextEditingController _cityController;
  late final TextEditingController _instagramController;
  late final TextEditingController _registrationNumberController;
  late final TextEditingController _tinController;
  late final TextEditingController _bankNameController;
  late final TextEditingController _accountNameController;
  late final TextEditingController _accountNumberController;
  late final TextEditingController _networkController;
  late final TextEditingController _payoutPhoneController;
  late final TextEditingController _settlementPreferenceController;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadedUid;
  bool _isRegisteredBusiness = false;
  String _payoutMethod = 'mobile-money';
  bool _agreedToPayoutTerms = false;
  bool _agreesToCompliance = false;
  String _reviewNotes = '';
  String _organizationId = '';
  String _logoFileName = '';
  String _logoImageUrl = '';
  String _governmentIdFileName = '';
  String _governmentIdUrl = '';
  String _selfieFileName = '';
  String _selfieUrl = '';
  _PickedImage? _logoImage;
  _PickedImage? _governmentIdImage;
  _PickedImage? _selfieImage;

  @override
  void initState() {
    super.initState();
    _organizerNameController = TextEditingController();
    _contactPersonController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _businessTypeController = TextEditingController();
    _businessAddressController = TextEditingController();
    _cityController = TextEditingController(text: 'Accra');
    _instagramController = TextEditingController();
    _registrationNumberController = TextEditingController();
    _tinController = TextEditingController();
    _bankNameController = TextEditingController();
    _accountNameController = TextEditingController();
    _accountNumberController = TextEditingController();
    _networkController = TextEditingController(text: 'MTN Mobile Money');
    _payoutPhoneController = TextEditingController();
    _settlementPreferenceController = TextEditingController(
      text: 'After event ends',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewer = Provider.of<EventoraSessionController>(
      context,
      listen: true,
    ).viewer;
    if (_loadedUid == viewer.uid && !_isLoading) {
      return;
    }
    _loadedUid = viewer.uid;
    _hydrateForViewer(viewer);
  }

  @override
  void dispose() {
    _organizerNameController.dispose();
    _contactPersonController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _businessTypeController.dispose();
    _businessAddressController.dispose();
    _cityController.dispose();
    _instagramController.dispose();
    _registrationNumberController.dispose();
    _tinController.dispose();
    _bankNameController.dispose();
    _accountNameController.dispose();
    _accountNumberController.dispose();
    _networkController.dispose();
    _payoutPhoneController.dispose();
    _settlementPreferenceController.dispose();
    super.dispose();
  }

  bool get _isBankTransfer => _payoutMethod == 'bank-transfer';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<EventoraSessionController>();
    final viewer = session.viewer;
    final palette = context.palette;
    final status = viewer.organizerApplicationStatus;
    final canEdit = viewer.canStartOrganizerApplication;
    final stepStates = _buildStepStates();

    return Scaffold(
      appBar: AppBar(title: const Text('Host access')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    _HostAccessHero(
                      statusLabel: viewer.organizerStatusLabel,
                      isGuest: viewer.isGuest,
                      canEdit: canEdit,
                      reviewNotes: _reviewNotes,
                    ),
                    const SizedBox(height: 20),
                    _StepStrip(stepStates: stepStates),
                    const SizedBox(height: 20),
                    if (viewer.isGuest) ...[
                      _GuestAccessCard(
                        onCreateAccount: () => _openSignUp(context),
                        onSignIn: () => _openSignIn(context),
                      ),
                    ] else if (canEdit) ...[
                      if (_reviewNotes.trim().isNotEmpty &&
                          status == OrganizerApplicationStatus.rejected) ...[
                        _StatusNoticeCard(
                          title: 'Updates requested',
                          body:
                              'Review the latest note, update your details, then resubmit your host access request.',
                          badgeLabel: 'Needs changes',
                          badgeColor: palette.coral,
                          reviewNotes: _reviewNotes,
                        ),
                        const SizedBox(height: 16),
                      ],
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _SectionCard(
                              title: 'Organizer profile',
                              subtitle:
                                  'This is the identity the Eventora team reviews before unlocking publishing.',
                              child: Column(
                                children: [
                                  _LogoPickerCard(
                                    fileName:
                                        _logoImage?.file.name.isNotEmpty == true
                                        ? _logoImage!.file.name
                                        : _logoFileName,
                                    onPick: () => _pickImage(_UploadSlot.logo),
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: _organizerNameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Organizer name',
                                    ),
                                    validator: _requiredField(
                                      'Add the organizer or brand name.',
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _contactPersonController,
                                    decoration: const InputDecoration(
                                      labelText: 'Contact person',
                                    ),
                                    validator: _requiredField(
                                      'Add the main contact person.',
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(
                                      labelText: 'Contact email',
                                    ),
                                    validator: (value) {
                                      final trimmed = value?.trim() ?? '';
                                      if (trimmed.isEmpty ||
                                          !trimmed.contains('@')) {
                                        return 'Enter a valid email address.';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(
                                      labelText: 'Contact number',
                                    ),
                                    validator: _requiredField(
                                      'Add the number your team can answer.',
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _businessTypeController,
                                    decoration: const InputDecoration(
                                      labelText: 'Business type',
                                      hintText:
                                          'Event Organizer, Venue, Festival, Community...',
                                    ),
                                    validator: _requiredField(
                                      'Tell us what kind of host you are.',
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _cityController,
                                    decoration: const InputDecoration(
                                      labelText: 'Primary city',
                                    ),
                                    validator: _requiredField(
                                      'Add the city you usually host in.',
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _businessAddressController,
                                    minLines: 2,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      labelText: 'Business address',
                                    ),
                                    validator: _requiredField(
                                      'Add the business address or operating base.',
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _instagramController,
                                    decoration: const InputDecoration(
                                      labelText: 'Instagram (optional)',
                                      hintText: '@yourbrand',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _SectionCard(
                              title: 'Verification details',
                              subtitle:
                                  'Share the documents and business details that make review easier.',
                              child: Column(
                                children: [
                                  _UploadTile(
                                    label: 'Government ID',
                                    helper:
                                        'Upload a photo of a national ID, passport, or driver licence.',
                                    fileName:
                                        _governmentIdImage
                                                ?.file
                                                .name
                                                .isNotEmpty ==
                                            true
                                        ? _governmentIdImage!.file.name
                                        : _governmentIdFileName,
                                    onPick: () =>
                                        _pickImage(_UploadSlot.governmentId),
                                  ),
                                  const SizedBox(height: 12),
                                  _UploadTile(
                                    label: 'Selfie / verification photo',
                                    helper:
                                        'Optional, but helpful when the reviewer needs a clearer identity match.',
                                    fileName:
                                        _selfieImage?.file.name.isNotEmpty ==
                                            true
                                        ? _selfieImage!.file.name
                                        : _selfieFileName,
                                    onPick: () =>
                                        _pickImage(_UploadSlot.selfie),
                                  ),
                                  const SizedBox(height: 12),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    value: _isRegisteredBusiness,
                                    onChanged: (value) => setState(
                                      () => _isRegisteredBusiness = value,
                                    ),
                                    title: const Text('Registered business'),
                                    subtitle: const Text(
                                      'Turn this on if the organizer operates as a registered company or organization.',
                                    ),
                                  ),
                                  if (_isRegisteredBusiness) ...[
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _registrationNumberController,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Business registration number',
                                      ),
                                      validator: (value) {
                                        if (!_isRegisteredBusiness) {
                                          return null;
                                        }
                                        if ((value ?? '').trim().isEmpty) {
                                          return 'Add the registration number.';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _tinController,
                                    decoration: const InputDecoration(
                                      labelText: 'TIN number (optional)',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _SectionCard(
                              title: 'Payout setup',
                              subtitle:
                                  'Use the destination your team expects to reconcile against live ticket sales.',
                              child: Column(
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: _payoutMethod,
                                    decoration: const InputDecoration(
                                      labelText: 'Payout method',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'mobile-money',
                                        child: Text('Mobile money'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'bank-transfer',
                                        child: Text('Bank transfer'),
                                      ),
                                    ],
                                    onChanged: (value) => setState(
                                      () => _payoutMethod =
                                          value ?? _payoutMethod,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  if (_isBankTransfer) ...[
                                    TextFormField(
                                      controller: _bankNameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Bank name',
                                      ),
                                      validator: _requiredWhen(
                                        _isBankTransfer,
                                        'Add the bank name.',
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _accountNameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Account name',
                                      ),
                                      validator: _requiredWhen(
                                        _isBankTransfer,
                                        'Add the account name.',
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _accountNumberController,
                                      decoration: const InputDecoration(
                                        labelText: 'Account number',
                                      ),
                                      validator: _requiredWhen(
                                        _isBankTransfer,
                                        'Add the account number.',
                                      ),
                                    ),
                                  ] else ...[
                                    TextFormField(
                                      controller: _networkController,
                                      decoration: const InputDecoration(
                                        labelText: 'Mobile money network',
                                      ),
                                      validator: _requiredWhen(
                                        !_isBankTransfer,
                                        'Add the mobile money network.',
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _payoutPhoneController,
                                      keyboardType: TextInputType.phone,
                                      decoration: const InputDecoration(
                                        labelText: 'Payout phone number',
                                      ),
                                      validator: _requiredWhen(
                                        !_isBankTransfer,
                                        'Add the payout number.',
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _settlementPreferenceController,
                                    decoration: const InputDecoration(
                                      labelText: 'Settlement preference',
                                    ),
                                    validator: _requiredField(
                                      'Tell us when you expect payouts.',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: _agreedToPayoutTerms,
                                    onChanged: (value) => setState(
                                      () =>
                                          _agreedToPayoutTerms = value ?? false,
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: const Text(
                                      'I agree to Eventora payout review and settlement controls.',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _SectionCard(
                              title: 'Final review',
                              subtitle:
                                  'Submit only when the details above match how your team actually operates.',
                              child: Column(
                                children: [
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: _agreesToCompliance,
                                    onChanged: (value) => setState(
                                      () =>
                                          _agreesToCompliance = value ?? false,
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: const Text(
                                      'I confirm these details are accurate and I agree to Eventora compliance review.',
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: _isSaving
                                              ? null
                                              : _saveDraft,
                                          child: Text(
                                            _isSaving
                                                ? 'Saving...'
                                                : 'Save progress',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _isSaving
                                              ? null
                                              : _submitForReview,
                                          child: Text(
                                            _isSaving
                                                ? 'Submitting...'
                                                : 'Submit for review',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      _StatusNoticeCard(
                        title: viewer.hasOrganizerAccess
                            ? 'Host access is active'
                            : viewer.hasPendingOrganizerApplication
                            ? 'Your request is in review'
                            : 'Host access status',
                        body: viewer.hasOrganizerAccess
                            ? 'Your account is ready for hosting. Use the Host tab to manage events, tickets, and campaign placements.'
                            : 'Your submission is already with the Eventora team. We will unlock publishing tools in the app as soon as review is complete.',
                        badgeLabel: viewer.organizerStatusLabel,
                        badgeColor:
                            viewer.hasOrganizerAccess
                            ? palette.teal
                            : palette.gold,
                        reviewNotes: _reviewNotes,
                      ),
                      const SizedBox(height: 16),
                      _SummarySection(
                        title: 'Organizer profile',
                        rows: [
                          _SummaryRowData(
                            label: 'Organizer',
                            value: _organizerNameController.text,
                          ),
                          _SummaryRowData(
                            label: 'Contact',
                            value: _contactPersonController.text,
                          ),
                          _SummaryRowData(
                            label: 'Email',
                            value: _emailController.text,
                          ),
                          _SummaryRowData(
                            label: 'Phone',
                            value: _phoneController.text,
                          ),
                          _SummaryRowData(
                            label: 'Business type',
                            value: _businessTypeController.text,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SummarySection(
                        title: 'Verification and payout',
                        rows: [
                          _SummaryRowData(
                            label: 'Government ID',
                            value: _governmentIdFileName,
                          ),
                          _SummaryRowData(
                            label: 'Registered business',
                            value: _isRegisteredBusiness ? 'Yes' : 'No',
                          ),
                          _SummaryRowData(
                            label: 'Payout method',
                            value: _isBankTransfer
                                ? 'Bank transfer'
                                : 'Mobile money',
                          ),
                          _SummaryRowData(
                            label: 'Settlement preference',
                            value: _settlementPreferenceController.text,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _hydrateForViewer(EventoraViewer viewer) async {
    if (!mounted) {
      return;
    }
    setState(() => _isLoading = true);
    if (viewer.isGuest || viewer.uid == null) {
      _applyDraft(EventoraOrganizerApplicationDraft.bootstrap(viewer));
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final draft = await EventoraOrganizerApplicationService.instance
          .loadDraft(viewer.uid!, viewer: viewer);
      if (!mounted) {
        return;
      }
      _applyDraft(draft ?? EventoraOrganizerApplicationDraft.bootstrap(viewer));
    } catch (_) {
      if (!mounted) {
        return;
      }
      _applyDraft(EventoraOrganizerApplicationDraft.bootstrap(viewer));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load host access details right now.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyDraft(EventoraOrganizerApplicationDraft draft) {
    _organizerNameController.text = draft.organizerName;
    _contactPersonController.text = draft.contactPerson;
    _emailController.text = draft.email;
    _phoneController.text = draft.phone;
    _businessTypeController.text = draft.businessType;
    _businessAddressController.text = draft.businessAddress;
    _cityController.text = draft.city;
    _instagramController.text = draft.instagram;
    _registrationNumberController.text = draft.businessRegistrationNumber;
    _tinController.text = draft.tinNumber;
    _bankNameController.text = draft.bankName;
    _accountNameController.text = draft.accountName;
    _accountNumberController.text = draft.accountNumber;
    _networkController.text = draft.network;
    _payoutPhoneController.text = draft.payoutPhone;
    _settlementPreferenceController.text = draft.settlementPreference;
    _isRegisteredBusiness = draft.isRegisteredBusiness;
    _payoutMethod = draft.payoutMethod;
    _agreedToPayoutTerms = draft.agreedToPayoutTerms;
    _agreesToCompliance = draft.agreesToCompliance;
    _reviewNotes = draft.reviewNotes;
    _organizationId = draft.organizationId;
    _logoFileName = draft.logoFileName;
    _logoImageUrl = draft.logoImageUrl;
    _governmentIdFileName = draft.governmentIdFileName;
    _governmentIdUrl = draft.governmentIdUrl;
    _selfieFileName = draft.selfieFileName;
    _selfieUrl = draft.selfieUrl;
    _logoImage = null;
    _governmentIdImage = null;
    _selfieImage = null;
  }

  EventoraOrganizerApplicationDraft _draftFromForm() {
    return EventoraOrganizerApplicationDraft(
      organizerName: _organizerNameController.text.trim(),
      contactPerson: _contactPersonController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      businessType: _businessTypeController.text.trim(),
      businessAddress: _businessAddressController.text.trim(),
      city: _cityController.text.trim(),
      instagram: _instagramController.text.trim(),
      logoFileName: _logoFileName,
      logoImageUrl: _logoImageUrl,
      governmentIdFileName: _governmentIdFileName,
      governmentIdUrl: _governmentIdUrl,
      selfieFileName: _selfieFileName,
      selfieUrl: _selfieUrl,
      isRegisteredBusiness: _isRegisteredBusiness,
      businessRegistrationNumber: _registrationNumberController.text.trim(),
      tinNumber: _tinController.text.trim(),
      payoutMethod: _payoutMethod,
      bankName: _bankNameController.text.trim(),
      accountName: _accountNameController.text.trim(),
      accountNumber: _accountNumberController.text.trim(),
      network: _networkController.text.trim(),
      payoutPhone: _payoutPhoneController.text.trim(),
      settlementPreference: _settlementPreferenceController.text.trim(),
      agreedToPayoutTerms: _agreedToPayoutTerms,
      agreesToCompliance: _agreesToCompliance,
      reviewNotes: _reviewNotes,
      organizationId: _organizationId,
    );
  }

  List<_StepState> _buildStepStates() {
    final brandReady =
        _organizerNameController.text.trim().isNotEmpty &&
        _contactPersonController.text.trim().isNotEmpty &&
        _businessTypeController.text.trim().isNotEmpty &&
        _businessAddressController.text.trim().isNotEmpty;
    final trustReady =
        _governmentIdFileName.trim().isNotEmpty &&
        (!_isRegisteredBusiness ||
            _registrationNumberController.text.trim().isNotEmpty);
    final payoutReady = _isBankTransfer
        ? _bankNameController.text.trim().isNotEmpty &&
              _accountNameController.text.trim().isNotEmpty &&
              _accountNumberController.text.trim().isNotEmpty &&
              _agreedToPayoutTerms
        : _networkController.text.trim().isNotEmpty &&
              _payoutPhoneController.text.trim().isNotEmpty &&
              _agreedToPayoutTerms;
    final reviewReady = _agreesToCompliance;

    return [
      _StepState(label: 'Brand', isComplete: brandReady),
      _StepState(label: 'Trust', isComplete: trustReady),
      _StepState(label: 'Payout', isComplete: payoutReady),
      _StepState(label: 'Review', isComplete: reviewReady),
    ];
  }

  String? Function(String?) _requiredField(String message) {
    return (value) {
      if ((value ?? '').trim().isEmpty) {
        return message;
      }
      return null;
    };
  }

  String? Function(String?) _requiredWhen(bool enabled, String message) {
    return (value) {
      if (!enabled) {
        return null;
      }
      if ((value ?? '').trim().isEmpty) {
        return message;
      }
      return null;
    };
  }

  Future<void> _pickImage(_UploadSlot slot) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 88,
    );
    if (picked == null || !mounted) {
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      switch (slot) {
        case _UploadSlot.logo:
          _logoImage = _PickedImage(file: picked, bytes: bytes);
        case _UploadSlot.governmentId:
          _governmentIdImage = _PickedImage(file: picked, bytes: bytes);
        case _UploadSlot.selfie:
          _selfieImage = _PickedImage(file: picked, bytes: bytes);
      }
    });
  }

  Future<void> _saveDraft() async {
    final session = context.read<EventoraSessionController>();
    final uid = session.viewer.uid;
    if (uid == null) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _uploadPendingImages(uid);
      await EventoraOrganizerApplicationService.instance.saveDraft(
        userId: uid,
        draft: _draftFromForm(),
      );
      await session.refreshViewer();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Host access progress saved.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save host access: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _submitForReview() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_governmentIdFileName.trim().isEmpty && _governmentIdImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload a government ID before submitting.'),
        ),
      );
      return;
    }
    if (!_agreedToPayoutTerms || !_agreesToCompliance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirm the payout and compliance checkboxes first.'),
        ),
      );
      return;
    }

    final session = context.read<EventoraSessionController>();
    final uid = session.viewer.uid;
    if (uid == null) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _uploadPendingImages(uid);
      await EventoraOrganizerApplicationService.instance.submit(
        userId: uid,
        draft: _draftFromForm(),
      );
      await session.refreshViewer();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Host access submitted for review.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit host access: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _uploadPendingImages(String uid) async {
    final service = EventoraOrganizerApplicationService.instance;

    if (_logoImage != null) {
      final uploaded = await service.uploadImage(
        userId: uid,
        kind: 'logo',
        bytes: _logoImage!.bytes,
        fileName: _logoImage!.file.name,
      );
      _logoFileName = uploaded.fileName;
      _logoImageUrl = uploaded.downloadUrl;
      _logoImage = null;
    }

    if (_governmentIdImage != null) {
      final uploaded = await service.uploadImage(
        userId: uid,
        kind: 'government-id',
        bytes: _governmentIdImage!.bytes,
        fileName: _governmentIdImage!.file.name,
      );
      _governmentIdFileName = uploaded.fileName;
      _governmentIdUrl = uploaded.downloadUrl;
      _governmentIdImage = null;
    }

    if (_selfieImage != null) {
      final uploaded = await service.uploadImage(
        userId: uid,
        kind: 'selfie',
        bytes: _selfieImage!.bytes,
        fileName: _selfieImage!.file.name,
      );
      _selfieFileName = uploaded.fileName;
      _selfieUrl = uploaded.downloadUrl;
      _selfieImage = null;
    }
  }

  Future<void> _openSignUp(BuildContext context) async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const SignUpScreen()));
  }

  Future<void> _openSignIn(BuildContext context) async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const SignInScreen()));
  }
}

class _HostAccessHero extends StatelessWidget {
  const _HostAccessHero({
    required this.statusLabel,
    required this.isGuest,
    required this.canEdit,
    required this.reviewNotes,
  });

  final String statusLabel;
  final bool isGuest;
  final bool canEdit;
  final String reviewNotes;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.98),
            palette.gold.withValues(alpha: 0.18),
            palette.coral.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0x1410212A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBadge(label: statusLabel, color: palette.ink),
          const SizedBox(height: 14),
          Text(
            isGuest
                ? 'Host access lives right here in the app.'
                : canEdit
                ? 'Set up your host access without leaving Eventora.'
                : 'Your host access profile is already in motion.',
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            isGuest
                ? 'Create or sign in to an Eventora account, then complete your organizer profile, verification details, and payout setup in this same flow.'
                : canEdit
                ? 'Finish the organizer profile, upload the verification details, and submit for review when everything looks right.'
                : reviewNotes.trim().isNotEmpty
                ? 'You can review the latest note here while the Eventora team processes your host access.'
                : 'Your existing host access details are saved in-app so you can keep track of status without opening a browser.',
            style: context.text.bodyLarge?.copyWith(color: palette.slate),
          ),
        ],
      ),
    );
  }
}

class _GuestAccessCard extends StatelessWidget {
  const _GuestAccessCard({
    required this.onCreateAccount,
    required this.onSignIn,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create your host account first',
              style: context.text.titleLarge?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 10),
            Text(
              'As soon as you sign in, you can complete the full host access flow here in the app and submit it for review.',
              style: context.text.bodyLarge,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onCreateAccount,
                child: const Text('Create account'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onSignIn,
                child: const Text('I already have an account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepStrip extends StatelessWidget {
  const _StepStrip({required this.stepStates});

  final List<_StepState> stepStates;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final step in stepStates)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: step.isComplete
                  ? palette.teal.withValues(alpha: 0.16)
                  : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: step.isComplete
                    ? palette.teal.withValues(alpha: 0.24)
                    : const Color(0x18121E31),
              ),
            ),
            child: Text(
              step.isComplete ? '${step.label} ready' : step.label,
              style: context.text.bodyMedium?.copyWith(
                color: step.isComplete ? palette.teal : palette.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.titleLarge?.copyWith(fontSize: 22)),
            const SizedBox(height: 8),
            Text(subtitle, style: context.text.bodyMedium),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _LogoPickerCard extends StatelessWidget {
  const _LogoPickerCard({required this.fileName, required this.onPick});

  final String fileName;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.white,
            child: Icon(Icons.storefront_outlined, color: palette.ink),
          ),
          const SizedBox(height: 12),
          Text(
            'Brand mark (optional)',
            style: context.text.titleLarge?.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            fileName.trim().isEmpty
                ? 'Add a logo or organizer mark so your host profile feels complete.'
                : fileName,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              fileName.trim().isEmpty ? 'Upload logo' : 'Change logo',
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.label,
    required this.helper,
    required this.fileName,
    required this.onPick,
  });

  final String label;
  final String helper;
  final String fileName;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.titleMedium),
          const SizedBox(height: 6),
          Text(
            fileName.trim().isEmpty ? helper : fileName,
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(
              fileName.trim().isEmpty ? 'Choose image' : 'Replace image',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusNoticeCard extends StatelessWidget {
  const _StatusNoticeCard({
    required this.title,
    required this.body,
    required this.badgeLabel,
    required this.badgeColor,
    this.reviewNotes,
  });

  final String title;
  final String body;
  final String badgeLabel;
  final Color badgeColor;
  final String? reviewNotes;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusBadge(label: badgeLabel, color: badgeColor),
            const SizedBox(height: 14),
            Text(title, style: context.text.titleLarge?.copyWith(fontSize: 22)),
            const SizedBox(height: 10),
            Text(body, style: context.text.bodyLarge),
            if ((reviewNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.palette.canvas,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  reviewNotes!,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.palette.ink,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.title, required this.rows});

  final String title;
  final List<_SummaryRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.titleLarge?.copyWith(fontSize: 20)),
            const SizedBox(height: 14),
            for (var index = 0; index < rows.length; index++) ...[
              _SummaryRow(row: rows[index]),
              if (index != rows.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.row});

  final _SummaryRowData row;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(row.label, style: context.text.bodyMedium),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            row.value.trim().isEmpty ? 'Not provided' : row.value,
            style: context.text.bodyLarge?.copyWith(color: context.palette.ink),
          ),
        ),
      ],
    );
  }
}

class _StepState {
  const _StepState({required this.label, required this.isComplete});

  final String label;
  final bool isComplete;
}

class _SummaryRowData {
  const _SummaryRowData({required this.label, required this.value});

  final String label;
  final String value;
}

class _PickedImage {
  const _PickedImage({required this.file, required this.bytes});

  final XFile file;
  final Uint8List bytes;
}

enum _UploadSlot { logo, governmentId, selfie }
