import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PresenceService {
  static final _firestore = FirebaseFirestore.instance;

  // Call when app comes to foreground
  static Future<void> setOnline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      'isOnline':  true,
      'lastSeen':  FieldValue.serverTimestamp(),
      'email':     user.email,
    }, SetOptions(merge: true));
  }

  // Call when app goes to background or user logs out
  static Future<void> setOffline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      'isOnline':  false,
      'lastSeen':  FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Stream of all online users
  static Stream<QuerySnapshot> get onlineUsers => _firestore
      .collection('users')
      .where('isOnline', isEqualTo: true)
      .snapshots();
}