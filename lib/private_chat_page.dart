import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'typing_service.dart';

class PrivateChatPage extends StatefulWidget {
  final String receiverId;
  final String receiverEmail;

  const PrivateChatPage({
    super.key,
    required this.receiverId,
    required this.receiverEmail,
  });

  @override
  State<PrivateChatPage> createState() => _PrivateChatPageState();
}

class _PrivateChatPageState extends State<PrivateChatPage> {
  final _messageCtrl = TextEditingController();
  final _firestore   = FirebaseFirestore.instance;
  final _auth        = FirebaseAuth.instance;
  final _picker      = ImagePicker();
  final _scrollCtrl  = ScrollController();
  bool _uploading    = false;

  // Generate a unique room ID from both user IDs
  // Sorting ensures A+B and B+A give the same room ID
  String get _roomId {
    final ids = [_auth.currentUser!.uid, widget.receiverId]..sort();
    return ids.join('_');
  }

  String get _currentEmail => _auth.currentUser!.email ?? '';
  String get _receiverName => widget.receiverEmail.split('@')[0];

  @override
  void dispose() {
    TypingService.setTyping(false, roomId: _roomId);
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Send text ──────────────────────────────────────────────
  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    final user = _auth.currentUser!;

    await _firestore
        .collection('chats')
        .doc(_roomId)
        .collection('messages')
        .add({
      'type':        'text',
      'text':        text,
      'senderId':    user.uid,
      'senderEmail': user.email,
      'timestamp':   FieldValue.serverTimestamp(),
    });

    // Update last message preview (like WhatsApp)
    await _firestore.collection('chats').doc(_roomId).set({
      'lastMessage':  text,
      'lastTime':     FieldValue.serverTimestamp(),
      'participants': [user.uid, widget.receiverId],
    }, SetOptions(merge: true));

    _messageCtrl.clear();
    await TypingService.setTyping(false, roomId: _roomId);
    _scrollToBottom();
  }

  // ── Send image ─────────────────────────────────────────────
  Future<void> _sendImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 40,
      maxWidth: 600,
    );
    if (picked == null) return;

    setState(() => _uploading = true);

    try {
      final user  = _auth.currentUser!;
      final bytes = await picked.readAsBytes();
      final base64Image = base64Encode(bytes);

      if (base64Image.length > 900000) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image too large.')),
        );
        return;
      }

      await _firestore
          .collection('chats')
          .doc(_roomId)
          .collection('messages')
          .add({
        'type':        'image',
        'imageBase64': base64Image,
        'senderId':    user.uid,
        'senderEmail': user.email,
        'timestamp':   FieldValue.serverTimestamp(),
      });

      await _firestore.collection('chats').doc(_roomId).set({
        'lastMessage':  '📷 Image',
        'lastTime':     FieldValue.serverTimestamp(),
        'participants': [user.uid, widget.receiverId],
      }, SetOptions(merge: true));

      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      setState(() => _uploading = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Stream<QuerySnapshot> get _messagesStream => _firestore
      .collection('chats')
      .doc(_roomId)
      .collection('messages')
      .orderBy('timestamp', descending: false)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    final currentUid = _auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.blue.shade100,
              child: Text(
                _receiverName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_receiverName,
                    style: const TextStyle(fontSize: 16)),

                // Show receiver's online status
                StreamBuilder<DocumentSnapshot>(
                  stream: _firestore
                      .collection('users')
                      .doc(widget.receiverId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data()
                        as Map<String, dynamic>?;
                    final isOnline = data?['isOnline'] ?? false;
                    return Text(
                      isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: isOnline ? Colors.green : Colors.grey,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [

          if (_uploading) const LinearProgressIndicator(),

          // ── Messages ─────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'Say hi to $_receiverName! 👋',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data =
                        docs[index].data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == currentUid;
                    return _MessageBubble(
                      type:        data['type'] ?? 'text',
                      text:        data['text'],
                      imageBase64: data['imageBase64'],
                      isMe:        isMe,
                      timestamp:   data['timestamp'] as Timestamp?,
                    );
                  },
                );
              },
            ),
          ),

          // ── Typing indicator ──────────────────────────
          StreamBuilder<DocumentSnapshot>(
            stream: _firestore
                .collection('typing')
                .doc('${_roomId}_${widget.receiverId}')
                .snapshots(),
            builder: (context, snapshot) {
              final data =
                  snapshot.data?.data() as Map<String, dynamic>?;
              final isTyping = data?['isTyping'] ?? false;
              if (!isTyping) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 4),
                child: Row(
                  children: [
                    Text(
                      '$_receiverName is typing',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(width: 4),
                    const _TypingDots(),
                  ],
                ),
              );
            },
          ),

          // ── Input bar ─────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border:
                  Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo, color: Colors.blue),
                  onPressed: _uploading ? null : _sendImage,
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: InputBorder.none,
                      ),
                      onChanged: (val) {
                        TypingService.setTyping(
                          val.isNotEmpty,
                          roomId: _roomId,
                        );
                      },
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }
}

// ── Animated typing dots ───────────────────────────────────────
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          children: List.generate(3, (i) {
            final opacity = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Message bubble ─────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final String type;
  final String? text;
  final String? imageBase64;
  final bool isMe;
  final Timestamp? timestamp;

  const _MessageBubble({
    required this.type,
    required this.isMe,
    this.text,
    this.imageBase64,
    this.timestamp,
  });

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final h  = dt.hour.toString().padLeft(2, '0');
    final m  = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(16),
            topRight:    const Radius.circular(16),
            bottomLeft:  Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (type == 'text')
              Text(
                text ?? '',
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              )
            else if (type == 'image' && imageBase64 != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  base64Decode(imageBase64!),
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 3),
            // Timestamp like WhatsApp
            Text(
              _formatTime(timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMe
                    ? Colors.white.withOpacity(0.7)
                    : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}