import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class DbService {
  static final _db = FirebaseFirestore.instance;

  // ---------- user bootstrap ----------
  static Future<void> ensureUserDoc() async {
    final uid = AuthService.uid!;
    final doc = _db.collection('users').doc(uid);
    final snap = await doc.get();
    if (!snap.exists) {
      await doc.set({
        'email': AuthService.email,
        'name': AuthService.displayName(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ---------- existing: breed counter ----------
  static Future<void> addBreed(String breed) async {
    final uid = AuthService.uid;
    if (uid == null) throw Exception('Not signed in');

    final userDoc = _db.collection('users').doc(uid);

    // keep your existing summary document update
    await userDoc.set({
      'email': AuthService.email,
      'name': AuthService.displayName(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // increment per-breed counter (as before)
    final ref = userDoc.collection('breeds').doc(breed);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final count = (snap.data()?['count'] ?? 0) as int;
      tx.set(ref, {'count': count + 1}, SetOptions(merge: true));
    });

    // NEW: also add a concrete animal row in "herd" so Herd screen can list it
    await userDoc.collection('herd').add({
      'breed': breed,
      'tagId': null, // editable later in Herd screen
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------- vaccinations (unchanged) ----------
  static Stream<QuerySnapshot<Map<String, dynamic>>> vaccStream() {
    final uid = AuthService.uid!;
    return _db
        .collection('users')
        .doc(uid)
        .collection('vaccinations')
        .orderBy('name')
        .snapshots();
  }

  static Future<void> setVaccination(String name, bool given) async {
    final uid = AuthService.uid!;
    final ref =
    _db.collection('users').doc(uid).collection('vaccinations').doc(name);
    await ref.set({
      'name': name,
      'given': given,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------- NEW: Herd helpers ----------
  static CollectionReference<Map<String, dynamic>> _herdCol() {
    final uid = AuthService.uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    return _db.collection('users').doc(uid).collection('herd');
  }

  /// Stream herd entries (newest first)
  static Stream<QuerySnapshot<Map<String, dynamic>>> herdStream() {
    return _herdCol().orderBy('createdAt', descending: true).snapshots();
  }

  /// Set or clear a 12-digit tag for a herd doc
  static Future<void> setHerdId(String docId, String? tag12) async {
    await _herdCol().doc(docId).update({'tagId': tag12});
  }

  /// Check uniqueness of a tag in your herd (excluding current doc)
  static Future<bool> herdIdExists(String tag12, {required String exceptDocId}) async {
    final qs =
    await _herdCol().where('tagId', isEqualTo: tag12).limit(2).get();
    for (final d in qs.docs) {
      if (d.id != exceptDocId) return true;
    }
    return false;
  }

  /// Optional: remove a herd entry
  static Future<void> removeHerdDoc(String docId) async {
    await _herdCol().doc(docId).delete();
  }
}