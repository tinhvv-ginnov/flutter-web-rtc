
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc_demo/src/call_sample/call_sample.dart';

class LoginPage extends StatefulWidget {

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  TextEditingController _nameController = TextEditingController();

  TextEditingController _idController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox(
              height: 16,
            ),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(hintText: 'Enter name'),
            ),
            SizedBox(
              height: 16,
            ),
            TextFormField(
              controller: _idController,
              decoration: InputDecoration(hintText: 'Enter Channel name'),
            ),
            SizedBox(
              height: 16,
            ),
            ElevatedButton(
                onPressed: () {
                  final code = _idController.text;
                  final name = _nameController.text;
                  if (code.isEmpty || name.isEmpty) return;
                  Navigator.push(context, MaterialPageRoute(builder: (context) => CallSample(code, name)));
                },
                child: Text('Join'))
          ],
        ),
      ),
    );
  }
}