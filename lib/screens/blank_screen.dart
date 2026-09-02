// ignore_for_file: file_names

import 'package:flutter/material.dart';

class BlankPage extends StatelessWidget {
  final String title;

  const BlankPage({super.key, this.title = 'Blank Page'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(title),
      ),
      body: Center(
        child: Text('This is $title'),
      ),
    );
  }
}
