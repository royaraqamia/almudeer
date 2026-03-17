import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../core/constants/colors.dart';
import '../../../core/api/api_client.dart';

/// Mention autocomplete dropdown that appears when typing @username
class MentionAutocomplete extends StatefulWidget {
  final String query;
  final double offsetX;
  final double offsetY;
  final Function(String username) onMentionSelected;
  final VoidCallback? onDismiss;

  const MentionAutocomplete({
    super.key,
    required this.query,
    required this.offsetX,
    required this.offsetY,
    required this.onMentionSelected,
    this.onDismiss,
  });

  @override
  State<MentionAutocomplete> createState() => _MentionAutocompleteState();
}

class _MentionAutocompleteState extends State<MentionAutocomplete>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  int _selectedIndex = 0;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  final ApiClient _apiClient = ApiClient();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
    _searchUsers();
  }

  @override
  void didUpdateWidget(MentionAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query) {
      _selectedIndex = 0;
      _searchUsers();
    }
  }

  Future<void> _searchUsers() async {
    if (widget.query.length < 2) {
      setState(() => _results = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _apiClient.get(
        '/api/users/search?q=${widget.query}&limit=10',
      );

      if (response['results'] != null) {
        setState(() {
          _results = List<Map<String, dynamic>>.from(
            (response['results'] as List).map((e) => Map<String, dynamic>.from(e)),
          );
        });
      }
    } catch (e) {
      // Silently fail - autocomplete is optional
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _selectUser(int index) {
    if (index >= 0 && index < _results.length) {
      final username = _results[index]['username'] as String;
      widget.onMentionSelected(username);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_results.isEmpty && !_isLoading) {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 250),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: Colors.transparent,
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final user = _results[index];
                      final isSelected = index == _selectedIndex;
                      final username = user['username'] as String;
                      final fullName = user['name'] as String?;

                      return InkWell(
                        onTap: () => _selectUser(index),
                        onHover: (hovering) {
                          if (hovering) {
                            setState(() => _selectedIndex = index);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : null,
                            border: Border(
                              bottom: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.05),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Avatar placeholder
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    username[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '@$username',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    if (fullName != null && fullName.isNotEmpty)
                                      Text(
                                        fullName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  SolarBoldIcons.checkCircle,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
