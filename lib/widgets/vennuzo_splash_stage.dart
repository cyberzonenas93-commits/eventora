import 'package:flutter/material.dart';

class VennuzoSplashStage extends StatelessWidget {
  const VennuzoSplashStage({
    super.key,
    this.title,
    this.subtitle,
    this.showLoader = false,
  });

  final String? title;
  final String? subtitle;
  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Image(
          image: AssetImage('assets/logo-transparent.png'),
          width: 220,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
