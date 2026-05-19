import 'dart:io';
import 'dart:convert';           // ← for base64
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/notification_service.dart';
import 'package:image_picker/image_picker.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageCtrl = TextEditingController();
  final _firestore   = FirebaseFirestore.instance;
  final _auth        = FirebaseAuth.instance;
  final _picker      = ImagePicker();
  bool _uploading    = false;

  @override
void initState() {
 super.initState();
 NotificationService().listenForeground(context);
 
}

  

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    final user = _auth.currentUser!;
    await _firestore.collection('messages').add({
      'type':        'text',
      'text':        text,
      'senderId':    user.uid,
      'senderEmail': user.email,
      'timestamp':   FieldValue.serverTimestamp(),
    });
    _messageCtrl.clear();
  }

Future<void> _sendImage() async {
  final picked = await _picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 40,
    maxWidth: 600,
  );
  if (picked == null) return;

  setState(() => _uploading = true);

  try {
    final user = _auth.currentUser!;

    // ← this is the fix: use picked.readAsBytes() instead of File()
    final bytes = await picked.readAsBytes();
    final base64Image = base64Encode(bytes);

    if (base64Image.length > 900000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image too large. Pick a smaller one.')),
      );
      return;
    }

    await _firestore.collection('messages').add({
      'type':        'image',
      'imageBase64': base64Image,
      'senderId':    user.uid,
      'senderEmail': user.email,
      'timestamp':   FieldValue.serverTimestamp(),
    });
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to send image: $e')),
    );
  } finally {
    setState(() => _uploading = false);
  }
}

  Stream<QuerySnapshot> get _messagesStream => _firestore
      .collection('messages')
      .orderBy('timestamp', descending: false)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Room'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [

          if (_uploading)
            const LinearProgressIndicator(),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No messages yet!'));
                }
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == currentUserId;
                    return _MessageBubble(
                      type:        data['type'] ?? 'text',
                      text:        data['text'],
                      imageBase64: data['imageBase64'],
                      senderEmail: data['senderEmail'] ?? 'Unknown',
                      isMe:        isMe,
                    );
                  },
                );
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo, color: Colors.blue),
                  onPressed: _uploading ? null : _sendImage,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }
}

// ── Message bubble ─────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final String type;
  final String? text;
  final String? imageBase64;
  final String senderEmail;
  final bool isMe;

  const _MessageBubble({
    required this.type,
    required this.senderEmail,
    required this.isMe,
    this.text,
    this.imageBase64,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey.shade200,
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(16),
            topRight:    const Radius.circular(16),
            bottomLeft:  Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              senderEmail,
              style: TextStyle(
                fontSize: 11,
                color: isMe ? Colors.blue.shade100 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),

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
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  base64Decode(imageBase64!),   // decode base64 → raw bytes
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
          ],
        ),
      ),
    );
  }
}