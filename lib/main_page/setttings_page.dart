import 'package:banking_app/login%20pages/sign_in_page.dart';
import 'package:banking_app/login%20pages/signup_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';

import 'help_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _password;
  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('Settings',
        style: TextStyle(
          fontSize: 18
        ),
        ),
      ),
      body: Column(
        children: [
          ListTile(
            title: Text(
              'Help',
              style: th.textTheme.bodySmall,
            ),
            leading: Icon(Icons.help_outline,),
            trailing: Icon(Icons.arrow_forward_ios, size: 16,),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context){
                return HelpPage();
              }));
            },
          ),
          SizedBox(
              width: MediaQuery.of(context).size.width,
              child: TextButton(
                  onPressed: () {
                    showModalBottomSheet(
                        context: context,
                        isDismissible: false,
                        builder: (context) {
                          return deleteAccount(AnimationController(
                              vsync: Navigator.of(context)));
                        });
                  },
                  child: Text('I\'ll want to delete my account')))
        ],
      ),
    );
  }

  BottomSheet deleteAccount(AnimationController animationController) {
    return BottomSheet(
        dragHandleColor: Colors.grey.shade100,
        backgroundColor: Colors.white,
        animationController: animationController,
        enableDrag: true,
        onClosing: () {},
        builder: (context) {
          return Builder(builder: (context) {
            return Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 10,),
                    Text(
                      'Attention',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 15,),
                    Text(
                      'Deleting your account is permanent and cannot be undone. All your data, history, and API usage, will be removed.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    SizedBox(height: 10,),
                    Divider(
                      color: Colors.grey.shade100,
                    ),
                    SizedBox(
                      width: MediaQuery.of(context).size.width,
                      child: Row(
                        children: [
                          SizedBox(
                            height: 40,
                            width: MediaQuery.of(context).size.width * 0.45,
                            child: dangerButton(
                              text: 'Delete',
                              onPressed: () async {
                                deleteUserData(context);
                              },
                            ),
                          ),
                          SizedBox(height: 10,),
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 0.45,
                            child: TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: Text('Cancel'),
                            ),
                          )
                        ],
                      ),
                    )
                  ]),
            );
          });
        });
  }

  ElevatedButton dangerButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      child: Text(text,
      style: TextStyle(
        color: Colors.white
      ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> deleteUserData(BuildContext context) async {
    try {
      // Get current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user currently logged in');
      }
      final userId = user.uid;
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .delete();
      QuerySnapshot trackItemsSnapshot = await FirebaseFirestore.instance
          .collection('track_items')
          .get();
      List<Future<void>> deletionTasks = trackItemsSnapshot.docs.map((doc) {
        // Notice we removed the async keyword here and return the Future directly
        return FirebaseFirestore.instance
            .collection('track_items')
            .doc(doc.id)
            .collection('monthUsers')
            .doc(userId)
            .get()
            .then((userMonthDoc) {
          if (userMonthDoc.exists) {
            return userMonthDoc.reference.delete();
          }
          return Future.value();
        });
      }).toList();
      await Future.wait(deletionTasks);
      // 4. Delete the user's authentication account
      await user.delete();
      // 5. Sign out after deletion
      await FirebaseAuth.instance.signOut();
      // 6. Check if context is still valid and navigate
      if (context.mounted) {
        // Use a post-frame callback to ensure navigation happens after the current frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => SignupPage()),
          );
        });
      }
    } catch (e) {
      print('Error during deletion: ${e.toString()}');
      if (e is FirebaseAuthException) {
        if (e.code == 'requires-recent-login') {
          // Prompt user to re-authenticate
          await _handleReauthentication(context);
          return;
        }
        _showErrorDialog('Authentication Error', e.message ?? 'An error occurred', context);
      } else {
        _showErrorDialog('Error', 'Failed to delete account: ${e.toString()}', context);
      }
    }
  }

// Helper function to handle re-authentication
  Future<void> _handleReauthentication(BuildContext context) async {
    try {
      // Show re-authentication dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Re-authenticate Required'),
          content: const Text('Please re-enter your password to delete your account'),
          actions: [
            TextFormField(
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
              ),
              onChanged: (value) {
                _password = value;
              },
            ),
            ElevatedButton(
              onPressed: () async {
                // Re-authenticate user
                final user = FirebaseAuth.instance.currentUser;
                if (user?.email != null) {
                  AuthCredential credential = EmailAuthProvider.credential(
                    email: user!.email!,
                    password: _password!, // Get from TextField
                  );
                  await user.reauthenticateWithCredential(credential);
                  // Try deletion again
                  Navigator.of(context).pop();
                  await deleteUserData(context);
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorDialog('Error', 'Failed to re-authenticate: ${e.toString()}',context);
    }
  }

// Helper function to show error dialog
  void _showErrorDialog(String title, String message,BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
