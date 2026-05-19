import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TypingService {
  static final _firestore = FirebaseFirestore.instance;
  static String get _uid => FirebaseAuth.instance.currentUser!.uid;

  // roomId makes typing per-conversation, not global
  static Future<void> setTyping(bool isTyping, {required String roomId}) async {
    await _firestore
        .collection('typing')
        .doc('${roomId}_$_uid')
        .set({
      'isTyping': isTyping,
      'uid':      _uid,
      'roomId':   roomId,
    });
  }
}