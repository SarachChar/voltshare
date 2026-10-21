import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voltshare_app/models/payment_method_model.dart';

abstract class PaymentMethodService {
  /// Returns the cards saved by [userId]: the default card first, then the
  /// rest most-recently-added first.
  Future<List<PaymentMethod>> getPaymentMethods(String userId);

  /// Inserts a saved card for [userId] and returns the stored row.
  ///
  /// MOCK ONLY: stores the card details directly. For production, swap this for
  /// a provider that tokenizes the card and store only the token + last 4.
  Future<PaymentMethod> addPaymentMethod({
    required String userId,
    required String cardNumber,
    required String holderName,
    required int expMonth,
    required int expYear,
    bool isDefault,
  });

  /// Removes a saved card by [id].
  Future<void> deletePaymentMethod(String id);

  /// Makes the card [id] the user's default: clears the default flag on all of
  /// [userId]'s other cards, then sets it on [id].
  Future<void> setDefaultPaymentMethod({
    required String userId,
    required String id,
  });
}

/// Supabase-backed implementation reading from the `payment_methods` table.
class PaymentMethodSupabaseService implements PaymentMethodService {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<List<PaymentMethod>> getPaymentMethods(String userId) async {
    final List<dynamic> data = await _client
        .from('payment_methods')
        .select()
        .eq('user_id', userId)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);

    return data
        .map((item) => PaymentMethod.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PaymentMethod> addPaymentMethod({
    required String userId,
    required String cardNumber,
    required String holderName,
    required int expMonth,
    required int expYear,
    bool isDefault = false,
  }) async {
    final data = await _client
        .from('payment_methods')
        .insert({
          'user_id': userId,
          'card_number': cardNumber,
          'holder_name': holderName,
          'exp_month': expMonth,
          'exp_year': expYear,
          'is_default': isDefault,
        })
        .select()
        .single();

    return PaymentMethod.fromJson(data);
  }

  @override
  Future<void> deletePaymentMethod(String id) async {
    await _client.from('payment_methods').delete().eq('id', id);
  }

  @override
  Future<void> setDefaultPaymentMethod({
    required String userId,
    required String id,
  }) async {
    // Clear the current default(s) first so the one-default-per-user unique
    // index isn't violated, then promote the chosen card. Scoped to the user's
    // own rows (RLS also enforces this).
    await _client
        .from('payment_methods')
        .update({'is_default': false})
        .eq('user_id', userId)
        .eq('is_default', true);

    await _client
        .from('payment_methods')
        .update({'is_default': true})
        .eq('id', id);
  }
}
