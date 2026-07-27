import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nicknameController;
  late TextEditingController _emailController;
  late TextEditingController _countryController;
  late TextEditingController _regionController;
  late TextEditingController _bioController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AuthBloc>().state;
    String nickname = '';
    String email = '';
    String country = '';
    String region = '';
    String bio = '';

    if (state is AuthAuthenticated) {
      nickname = state.nickname ?? '';
      email = state.email ?? '';
      country = state.country ?? '';
      region = state.regionName ?? '';
      bio = state.bio ?? '';
    }

    _nicknameController = TextEditingController(text: nickname);
    _emailController = TextEditingController(text: email);
    _countryController = TextEditingController(text: country);
    _regionController = TextEditingController(text: region);
    _bioController = TextEditingController(text: bio);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _countryController.dispose();
    _regionController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      context.read<AuthBloc>().add(AuthUpdateProfileRequested(
        nickname: _nicknameController.text,
        email: _emailController.text,
        country: _countryController.text,
        regionName: _regionController.text,
        bio: _bioController.text,
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.success),
            backgroundColor: AppColors.successLight,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.errorLight,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          l10n.editProfile,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: _isLoading
                ? SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.w,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  )
                : Text(
                    l10n.save,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16.w),
          children: [
            _buildSection(
              title: l10n.personalInfo,
              children: [
                _buildTextField(
                  controller: _nicknameController,
                  label: l10n.nickname,
                  icon: Icons.person_outline,
                ),
                _buildTextField(
                  controller: _emailController,
                  label: l10n.email,
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
            SizedBox(height: 16.h),
            _buildSection(
              title: l10n.locationInfo,
              children: [
                _buildTextField(
                  controller: _countryController,
                  label: l10n.country,
                  icon: Icons.flag_outlined,
                ),
                _buildTextField(
                  controller: _regionController,
                  label: l10n.region,
                  icon: Icons.location_on_outlined,
                ),
              ],
            ),
            SizedBox(height: 16.h),
            _buildSection(
              title: l10n.aboutMe,
              children: [
                _buildTextField(
                  controller: _bioController,
                  label: l10n.bio,
                  icon: Icons.info_outline,
                  maxLines: 3,
                ),
              ],
            ),
            SizedBox(height: 32.h),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 24.w,
                      height: 24.w,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.w,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      l10n.save,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.w, 16.w, 8.w),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.w),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20.sp),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        ),
      ),
    );
  }
}
