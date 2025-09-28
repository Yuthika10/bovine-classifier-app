import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../widgets/appbars.dart';
import '../widgets/drawer_menu.dart';
import 'package:flutter/services.dart';

class HerdScreen extends StatelessWidget {
  const HerdScreen({super.key});

  Future<void> _editIdDialog(
      BuildContext context, {
        required String docId,
        required String? currentId,
      }) async {
    final ctrl = TextEditingController(text: currentId ?? '');
    String? err;

    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Assign 12-digit ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12),
              ],
              decoration: InputDecoration(
                hintText: 'Eg. 123456789012',
                errorText: err,
              ),
              onChanged: (_) {
                if (err != null) {
                  // clear validation error while typing
                  err = null;
                }
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'ID must be exactly 12 digits and unique in your herd.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final value = ctrl.text.trim();
              // basic validation
              if (value.length != 12) {
                err = 'ID must be exactly 12 digits';
                (c as Element).markNeedsBuild();
                return;
              }
              if (!RegExp(r'^\d{12}$').hasMatch(value)) {
                err = 'Digits only (0–9)';
                (c as Element).markNeedsBuild();
                return;
              }

              // Uniqueness check
              final exists = await DbService.herdIdExists(value, exceptDocId: docId);
              if (exists) {
                err = 'That ID is already used';
                (c as Element).markNeedsBuild();
                return;
              }

              try {
                await DbService.setHerdId(docId, value);
                if (context.mounted) Navigator.pop(c);
              } catch (e) {
                err = '$e';
                (c as Element).markNeedsBuild();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topLevelAppBar('My Herd'),
      drawer: const DrawerMenu(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: DbService.herdStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? const [];

          if (docs.isEmpty) {
            return const Center(child: Text('No animals in your herd yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = docs[i];
              final data = d.data();
              final breed = (data['breed'] ?? '').toString();
              final tag = (data['tagId'] ?? '').toString();
              final created = (data['createdAt'] as Timestamp?)?.toDate();

              return ListTile(
                leading: const CircleAvatar(child: Text('🐄')),
                title: Text(breed.isEmpty ? 'Unknown breed' : breed,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tag.isEmpty ? 'ID: —' : 'ID: $tag'),
                    if (created != null)
                      Text('Added: ${created.toLocal()}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
                trailing: TextButton.icon(
                  onPressed: () => _editIdDialog(context, docId: d.id, currentId: tag.isEmpty ? null : tag),
                  icon: const Icon(Icons.edit),
                  label: const Text('Set ID'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}