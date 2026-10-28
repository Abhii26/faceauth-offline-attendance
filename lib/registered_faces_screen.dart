import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/formatters.dart';
import 'core/theme.dart';
import 'services/database_service.dart';
import 'widgets/ui.dart';

/// Gallery of enrolled people with search and swipe/tap delete.
class RegisteredFacesScreen extends StatefulWidget {
  const RegisteredFacesScreen({super.key});

  @override
  State<RegisteredFacesScreen> createState() => _RegisteredFacesScreenState();
}

class _RegisteredFacesScreenState extends State<RegisteredFacesScreen> {
  List<FaceRecord> _faces = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final records = await DatabaseService.getFaces().timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() { _faces = records; _loading = false; });
    } catch (e, st) {
      debugPrint('[RegFacesScreen] load error: $e\n$st');
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _delete(FaceRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove person?'),
        content: Text('"${r.name}" will no longer be recognised. Past attendance records are kept.',
            style: const TextStyle(color: AppColors.textDim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseService.deleteFace(r.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _query.isEmpty
        ? _faces
        : _faces.where((f) => f.name.toLowerCase().contains(_query.toLowerCase())).toList();

    return AppScaffold(
      title: 'People',
      actions: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: StatusPill('${_faces.length} enrolled', AppColors.accent,
                icon: Icons.people_alt_rounded),
          ),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, color: AppColors.danger, size: 44),
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: AppColors.textDim)),
                    const SizedBox(height: 14),
                    TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry')),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.accent,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (_faces.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextField(
                            onChanged: (v) => setState(() => _query = v),
                            decoration: InputDecoration(
                              hintText: 'Search people',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      if (_faces.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Column(children: [
                            Icon(Icons.person_search_rounded,
                                size: 72, color: AppColors.textFaint),
                            SizedBox(height: 14),
                            Text('No one enrolled yet',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            SizedBox(height: 6),
                            Text('Use Register on the home screen to add a face.',
                                style: TextStyle(color: AppColors.textFaint)),
                          ]),
                        ),
                      for (int i = 0; i < list.length; i++)
                        FadeSlideIn(
                          index: i.clamp(0, 6),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Dismissible(
                              key: ValueKey(list[i].id),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) async {
                                await _delete(list[i]);
                                return false; // list is reloaded after delete
                              },
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 22),
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: const Icon(Icons.delete_outline_rounded,
                                    color: AppColors.danger),
                              ),
                              child: GlassCard(
                                padding: const EdgeInsets.all(12),
                                child: Row(children: [
                                  Container(
                                    padding: const EdgeInsets.all(2.5),
                                    decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: AppColors.brandGradient),
                                    child: ClipOval(
                                      child: Image.memory(list[i].imageBytes,
                                          width: 56, height: 56, fit: BoxFit.cover),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(list[i].name,
                                              style: const TextStyle(
                                                  fontSize: 16, fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 2),
                                          Text(
                                              list[i].createdAt == null
                                                  ? 'Enrolled'
                                                  : 'Enrolled ${Fmt.date(list[i].createdAt!)}',
                                              style: const TextStyle(
                                                  color: AppColors.textFaint, fontSize: 12)),
                                        ]),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded,
                                        color: AppColors.textFaint),
                                    onPressed: () => _delete(list[i]),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
