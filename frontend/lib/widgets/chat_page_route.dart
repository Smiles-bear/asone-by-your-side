import 'package:flutter/material.dart';

/// Only the single-conversation entrances opt into this transition.
class ChatPageRoute<T> extends MaterialPageRoute<T> {
  ChatPageRoute({required super.builder});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: child,
    );
  }
}
