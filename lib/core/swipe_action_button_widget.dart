import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'events.dart';
import 'swipe_action_cell.dart';
import 'swipe_data.dart';

class SwipeActionButtonWidget extends StatefulWidget {
  final int actionIndex;

  const SwipeActionButtonWidget({
    Key key,
    this.actionIndex,
  }) : super(key: key);

  @override
  _SwipeActionButtonWidgetState createState() {
    return _SwipeActionButtonWidgetState();
  }
}

class _SwipeActionButtonWidgetState extends State<SwipeActionButtonWidget>
    with TickerProviderStateMixin {
  double width;
  Alignment alignment;
  CompletionHandler handler;

  StreamSubscription pullLastButtonSubscription;
  StreamSubscription pullLastButtonToCoverCellEventSubscription;
  StreamSubscription closeNestedActionEventSubscription;

  bool whenNestedActionShowing;
  bool whenFirstAction;
  bool whenActiveToWidth;
  bool whenPullingOut;

  Alignment normalAlignment;

  SwipeData data;
  SwipeAction action;

  AnimationController widthPullController;
  AnimationController widthFillActionContentController;
  Animation<double> widthPullCurve;
  Animation<double> widthFillActionContentCurve;
  Animation animation;

  bool lockAnim;

  @override
  void initState() {
    super.initState();
    whenActiveToWidth = true;
    lockAnim = false;
    whenPullingOut = false;
    whenNestedActionShowing = false;
    whenFirstAction = widget.actionIndex == 0;
    width = 0;

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (action.forceAlignmentLeft) {
        alignment = Alignment.centerLeft;
      }
      _initAnim();
      _initCompletionHandler();
    });

    _listenEvent();
  }

  ///when full draggable,pull first action
  void _pullActionButton(bool isPullingOut) {
    _resetAnimationController(widthPullController);
    whenActiveToWidth = false;
    if (isPullingOut) {
      animation = Tween<double>(begin: width, end: data.currentOffset)
          .animate(widthPullCurve)
            ..addListener(() {
              if (lockAnim) return;
              width = animation.value;
              alignment = Alignment.lerp(
                  alignment, Alignment.centerLeft, widthPullController.value);
              setState(() {});
            });
      widthPullController.forward().whenComplete(() {
        whenActiveToWidth = true;
        whenPullingOut = true;
      });
    } else {
      final factor = data.currentOffset / data.totalActionWidth;
      double sumWidth = 0.0;
      for (int i = 0; i <= widget.actionIndex; i++) {
        sumWidth += data.actions[i].widthSpace;
      }
      final currentWidth = sumWidth * factor;
      animation = Tween<double>(begin: data.currentOffset, end: currentWidth)
          .animate(widthPullCurve)
            ..addListener(() {
              if (lockAnim) return;
              width = animation.value;
              alignment = Alignment.lerp(
                  alignment, normalAlignment, widthPullController.value);
              setState(() {});
            });
      widthPullController.forward().whenComplete(() {
        whenActiveToWidth = true;
        whenPullingOut = false;
      });
    }
  }

  void _listenEvent() {
    ///Cell layer has judged the value of performsFirstActionWithFullSwipe
    pullLastButtonSubscription = SwipeActionStore.getInstance()
        .bus
        .on<PullLastButtonEvent>()
        .listen((event) async {
      if (event.key == data.parentKey && whenFirstAction) {
        _pullActionButton(event.isPullingOut);
      }
    });

    pullLastButtonToCoverCellEventSubscription = SwipeActionStore.getInstance()
        .bus
        .on<PullLastButtonToCoverCellEvent>()
        .listen((event) {
      if (event.key == data.parentKey) {
        _animToCoverCell();
      }
    });

    closeNestedActionEventSubscription = SwipeActionStore.getInstance()
        .bus
        .on<CloseNestedActionEvent>()
        .listen((event) {
      if (event.key == data.parentKey &&
          action.nestedAction != null &&
          whenNestedActionShowing) {
        _resetNestedAction();
      }
      if (event.key != data.parentKey && whenNestedActionShowing) {
        _resetNestedAction();
      }
    });
  }

  void _resetNestedAction() {
    whenActiveToWidth = true;
    whenNestedActionShowing = false;
    alignment = normalAlignment;
    setState(() {});
  }

  void _initCompletionHandler() {
    if (action.onTap != null) {
      handler = (delete) async {
        if (delete) {
          SwipeActionStore.getInstance()
              .bus
              .fire(IgnorePointerEvent(ignore: true));

          if (data.firstActionWillCoverAllSpaceOnDeleting) {
            _animToCoverCell();

            ///and avoid layout jumping because of fast animation
            await Future.delayed(const Duration(milliseconds: 50));
          }
          data.parentState.deleteWithAnim();

          ///wait the animation to complete
          await Future.delayed(const Duration(milliseconds: 401));
        } else {
          if (action.closeOnTap) {
            data.parentState.closeWithAnim();
          }
        }
      };
    }
  }

  void _animToCoverCell() {
    _resetAnimationController(widthPullController);
    whenActiveToWidth = false;
    animation = Tween<double>(begin: width, end: data.contentWidth)
        .animate(widthPullCurve)
          ..addListener(() {
            if (lockAnim) return;
            width = animation.value;
            alignment = Alignment.lerp(
                alignment, Alignment.centerLeft, widthPullController.value);
            setState(() {});
          });
    widthPullController.forward();
  }

  void _animToCoverPullActionContent() async {
    if (action.nestedAction.nestedWidth != null) {
      try {
        assert(
            action.nestedAction.nestedWidth >= data.totalActionWidth,
            "Your nested width must be larger than the width of all action buttons"
            "\n 你的nestedWidth必须要大于或者等于所有按钮的总长度，否则下面的按钮会显现出来");
      } catch (e) {
        print(e.toString());
      }
    }

    _resetAnimationController(widthFillActionContentController);
    whenActiveToWidth = false;
    whenNestedActionShowing = true;
    alignment = Alignment.center;

    if (action.nestedAction.nestedWidth != null &&
        action.nestedAction.nestedWidth > data.totalActionWidth) {
      data.parentState.adjustOffset(
          offsetX: action.nestedAction.nestedWidth,
          curve: action.nestedAction.curve);
    }
    animation = Tween<double>(
            begin: width,
            end: action.nestedAction.nestedWidth ?? data.totalActionWidth)
        .animate(widthFillActionContentCurve)
          ..addListener(() {
            if (lockAnim) return;
            width = animation.value;
            alignment = Alignment.lerp(alignment, Alignment.center,
                widthFillActionContentController.value);
            setState(() {});
          });
    widthFillActionContentController.forward();
  }

  @override
  Widget build(BuildContext context) {
    data = SwipeData.of(context);
    action = data.actions[widget.actionIndex];
    final bool willPull = data.willPull && whenFirstAction;
    final bool isTheOnlyOne = data.actions.length == 1;

    final bool shouldShowNestedActionInfo = widget.actionIndex == 0 &&
        action.nestedAction != null &&
        whenNestedActionShowing;

    if (whenActiveToWidth) {
      if (!whenNestedActionShowing) {
        ///compute alignment
        alignment = data.actions.length == 1 && data.fullDraggable
            ? Alignment.centerRight
            : Alignment.centerLeft;

        if (action.forceAlignmentLeft) {
          alignment = Alignment.centerLeft;
        }

        ///save normal alignment
        normalAlignment = alignment;
        if (whenPullingOut) {
          alignment = Alignment.centerLeft;
        }

        ///compute width
        final currentPullWidth = data.currentOffset;
        if (willPull) {
          width = data.currentOffset;
        } else {
          final factor = currentPullWidth / data.totalActionWidth;
          double sumWidth = 0.0;
          for (int i = 0; i <= widget.actionIndex; i++) {
            sumWidth += data.actions[i].widthSpace;
          }
          width = sumWidth * factor;
        }
      }
    }

    return GestureDetector(
      onTap: () {
        if (whenFirstAction &&
            action.nestedAction != null &&
            !whenNestedActionShowing) {
          if (action.nestedAction.impactWhenShowing) {
            HapticFeedback.mediumImpact();
          }
          _animToCoverPullActionContent();
          return;
        }
        action.onTap?.call(handler);
      },
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(action.backgroundRadius),
                bottomLeft: Radius.circular(action.backgroundRadius)),
            color: action.color,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: alignment == Alignment.center ? 0 : action.leftPadding,
              right: isTheOnlyOne &&
                      !(action.forceAlignmentLeft) &&
                      data.fullDraggable
                  ? 16
                  : 0,
            ),
            child: Align(
              alignment: alignment,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _buildIcon(action, shouldShowNestedActionInfo),
                  _buildTitle(action, shouldShowNestedActionInfo),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(SwipeAction action, bool shouldShowNestedActionInfo) {
    return shouldShowNestedActionInfo
        ? action.nestedAction.icon ?? const SizedBox()
        : action.icon ?? const SizedBox();
  }

  Widget _buildTitle(SwipeAction action, bool shouldShowNestedActionInfo) {
    if (shouldShowNestedActionInfo) {
      if (action.nestedAction.title == null) return const SizedBox();
      return Text(
        action.nestedAction.title,
        overflow: TextOverflow.clip,
        maxLines: 1,
        style: action.style,
      );
    } else {
      if (action.title == null) return const SizedBox();
      return Text(
        action.title,
        overflow: TextOverflow.clip,
        maxLines: 1,
        style: action.style,
      );
    }
  }

  @override
  void dispose() {
    widthPullController?.dispose();
    widthFillActionContentController?.dispose();
    pullLastButtonSubscription?.cancel();
    pullLastButtonToCoverCellEventSubscription?.cancel();
    closeNestedActionEventSubscription?.cancel();
    super.dispose();
  }

  void _initAnim() {
    widthPullController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));

    widthPullCurve =
        CurvedAnimation(parent: widthPullController, curve: Curves.decelerate);

    if (widget.actionIndex == 0 && action.nestedAction != null) {
      widthFillActionContentController = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 250));
      widthFillActionContentCurve = CurvedAnimation(
          parent: widthFillActionContentController,
          curve: action.nestedAction.curve);
    }
  }

  void _resetAnimationController(AnimationController controller) {
    lockAnim = true;
    controller?.value = 0;
    lockAnim = false;
  }
}

class SwipeActionStore {
  static SwipeActionStore _instance;
  SwipeActionBus bus;

  static SwipeActionStore getInstance() {
    if (_instance == null) {
      _instance = SwipeActionStore();
      _instance.bus = SwipeActionBus();
    }
    return _instance;
  }
}
