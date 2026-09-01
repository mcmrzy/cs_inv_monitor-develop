import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/data/continents_data.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 国家/地区选择底部弹层。
///
/// 支持按国家/地区名称或代码筛选，选择后返回 `code` 与 `name`。
class AuthCountryPickerSheet extends StatefulWidget {
  const AuthCountryPickerSheet({super.key, required this.initialCode});

  final String initialCode;

  @override
  State<AuthCountryPickerSheet> createState() =>
      _AuthCountryPickerSheetState();
}

class _AuthCountryPickerSheetState extends State<AuthCountryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(Map<dynamic, dynamic> country) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final name = (country['name'] as String).toLowerCase();
    final code = (country['code'] as String).toLowerCase();
    return name.contains(query) || code.contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final children = <Widget>[];
    var matchCount = 0;

    for (final continent in continents) {
      final countries = (continent['countries'] as List<Map<dynamic, dynamic>>)
          .where(_matches)
          .toList();
      if (countries.isEmpty) continue;
      matchCount += countries.length;
      children.add(_buildContinentHeader(continent['name'] as String));
      for (final country in countries) {
        children.add(_buildCountryTile(country));
      }
    }

    return Container(
      height: 0.78.sh,
      decoration: BoxDecoration(
        color: AppColor.surface(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.str('auth_country_region'),
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 22.w,
                      color: AppColor.textSecondary(context),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: l10n.str('auth_search_country'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(height: 8.h),
            Expanded(
              child: matchCount == 0
                  ? Center(
                      child: Text(
                        l10n.str('auth_no_country_match'),
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColor.textSecondary(context),
                        ),
                      ),
                    )
                  : ListView(children: children),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinentHeader(String name) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
          color: AppColor.textSecondary(context),
        ),
      ),
    );
  }

  Widget _buildCountryTile(Map<dynamic, dynamic> country) {
    final code = country['code'] as String;
    final name = country['name'] as String;
    final selected = code == widget.initialCode;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(
        '$name ($code)',
        style: TextStyle(
          fontSize: 14.sp,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: AppColor.textPrimary(context),
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: AppColors.primary, size: 20.w)
          : null,
      onTap: () => Navigator.of(context).pop(
        <String, String>{'code': code, 'name': name},
      ),
    );
  }
}
