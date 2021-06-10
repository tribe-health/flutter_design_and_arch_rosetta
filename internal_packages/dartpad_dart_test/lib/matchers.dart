// Copyright 2021 Fredrick Allan Grott. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.
// Modified from the Dart project.
// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.


import 'package:matcher/matcher.dart';

/// The result of an [AsyncMatcher]'s match method.
class MatchResult {
  // ignore: avoid_positional_boolean_parameters
  MatchResult(this.isMatch, this.matchState);

  final bool isMatch;
  final Map<dynamic, dynamic> matchState;
}

/// Object capable of asynchronously testing values to see if they meet one or
/// more criteria, such as being of a specific type, having a property with a
/// particular value, etc.
abstract class AsyncMatcher {
  /// Determines if the [AsyncMatcher] considers [item] to be a match for its
  /// specific criteria.
  ///
  /// Note that if the match fails, the [MatchResult] returned will include
  /// [matchState], a Map containing data about the failed match. This map
  /// should be included to subsequent calls to [describeMismatch] in order to
  /// get an accurate text description of the failed match.
  Future<MatchResult> matchAsync(dynamic item);

  /// Builds a textual description of this [AsyncMatcher].
  Description describe(Description description);

  /// Builds a textual description of a particular failure to match.
  ///
  /// This should be called after [matchAsync], and the [matchState] from the
  /// resulting [MatchResult] should be provided to this method.
  Description describeMismatch(dynamic item, Description mismatchDescription,
          // ignore: avoid_positional_boolean_parameters
          Map matchState, bool verbose) =>
      mismatchDescription;
}

/// Wrapper class that adapts a [Matcher] from package:matcher to the API used
/// by [AsyncMatcher].
class MatcherToAsyncMatcherAdapter extends AsyncMatcher {
  final Matcher _matcher;

  /// Default constructor.
  ///
  /// If a literal value ("ABCD", 1234, etc.) is given as the argument, it will
  /// be wrapped in a [Matcher] via [wrapMatcher], then wrapped again by this
  /// class.
  MatcherToAsyncMatcherAdapter(dynamic unwrapped)
      : _matcher = wrapMatcher(unwrapped);

  /// Calls this [Matcher]'s [matches] method and couches the value returned in
  /// a Future<MatchResult>.
  @override
  Future<MatchResult> matchAsync(dynamic item) async {
    final matchState = <dynamic, dynamic>{};
    final isMatch = _matcher.matches(item, matchState);
    return MatchResult(isMatch, matchState);
  }

  /// Returns the description generated by this [Matcher]'s [describe] method
  /// with no modification.
  @override
  Description describe(Description description) =>
      _matcher.describe(description);

  /// Returns the mismatch description generated by the [Matcher]'s
  /// describeMismatch method with no modification.
  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
          Map<dynamic, dynamic> matchState, bool verbose) =>
      _matcher.describeMismatch(item, mismatchDescription, matchState, verbose);
}

/// Creates a CompletionMatcher.
///
/// This is included for parity with API found in the `test` package.
CompletionMatcher completion(dynamic matcher) => CompletionMatcher(matcher);

/// [AsyncMatcher[ that will wait for a future to complete, then test the
/// resulting value with another matcher.
///
/// If the future generates an error, the match automatically fails.
class CompletionMatcher extends AsyncMatcher {
  late AsyncMatcher  _innerMatcher;

  CompletionMatcher([dynamic unwrappedMatcher = anything])
      : assert(unwrappedMatcher != null) {
    if (unwrappedMatcher is AsyncMatcher) {
      _innerMatcher = unwrappedMatcher;
    } else {
      _innerMatcher =
          MatcherToAsyncMatcherAdapter(wrapMatcher(unwrappedMatcher));
    }
  }

  /// Waits for the future to complete, then matches the result against the
  /// the matcher provided in the constructor.
  @override
  Future<MatchResult> matchAsync(dynamic item) async {
    final matchState = <dynamic, dynamic>{};

    if (item == null) {
      matchState['invalid_item'] = 'was null.';
      return MatchResult(false, matchState);
    } else if (item is! Future) {
      matchState['invalid_item'] = 'was not a Future.';
      return MatchResult(false, matchState);
    } else {
      try {
        final dynamic innerItem = await item;
        final innerMatchResult = await _innerMatcher.matchAsync(innerItem);
        matchState['inner_item'] = innerItem;
        matchState['inner_match_state'] = innerMatchResult.matchState;
        return MatchResult(innerMatchResult.isMatch, matchState);
      } catch (err) {
        matchState['exception'] = err;
        return MatchResult(false, matchState);
      }
    }
  }

  /// Builds a textual description of this [CompletionMatcher].
  @override
  Description describe(Description description) {
    return description
      ..add('a Future that completes with ')
      ..addDescriptionOf(_innerMatcher);
  }

  /// Builds a textual description of a particular failure to match.
  ///
  /// This should be called after [matchAsync], and the [matchState] from the
  /// resulting [MatchResult] should be provided to this method.
  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
      Map matchState, bool verbose) {
    // this always true but I keep it for understanding
    // ignore: unnecessary_null_comparison
    if (matchState != null) {
      if (matchState.containsKey('invalid_item')) {
        mismatchDescription.add('${matchState['invalid_item']}');
      } else if (matchState.containsKey('exception')) {
        mismatchDescription
            .add('completed with an error: ${matchState['exception']}');
      } else if (matchState.containsKey('inner_match_state') &&
          matchState.containsKey('inner_item')) {
        mismatchDescription.add('was a Future that completed with ');
        return _innerMatcher.describeMismatch(
            matchState['inner_item'],
            mismatchDescription,
            matchState['inner_match_state'] as Map<dynamic, dynamic>,
            verbose);
      } else {
        mismatchDescription.add('was a Future that completed incorrectly.');
      }
    }

    return mismatchDescription;
  }
}
