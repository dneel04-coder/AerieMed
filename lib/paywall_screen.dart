import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'user_profile.dart';

const String kIapProductId = 'resqruck_full_access';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _sub;

  ProductDetails? _product;
  bool _loading = true;
  bool _purchasing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = _iap.purchaseStream.listen(_onPurchaseUpdate);
    _loadProduct();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    setState(() { _loading = true; _error = null; });
    final available = await _iap.isAvailable();
    if (!mounted) return;
    if (!available) {
      setState(() { _loading = false; _error = 'Store not available. Check your connection.'; });
      return;
    }
    final response = await _iap.queryProductDetails({kIapProductId});
    if (!mounted) return;
    if (response.error != null || response.notFoundIDs.isNotEmpty) {
      setState(() { _loading = false; _error = 'Product not found. Please try again later.'; });
      return;
    }
    setState(() {
      _product = response.productDetails.first;
      _loading = false;
    });
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID != kIapProductId) continue;
      if (p.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _purchasing = true);
      } else if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        await UserProfile.markUnlocked();
        if (mounted) Navigator.pop(context, true);
      } else if (p.status == PurchaseStatus.error) {
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        if (mounted) setState(() { _purchasing = false; _error = p.error?.message ?? 'Purchase failed.'; });
      } else if (p.status == PurchaseStatus.canceled) {
        if (mounted) setState(() => _purchasing = false);
      }
    }
  }

  Future<void> _buy() async {
    if (_product == null || _purchasing) return;
    setState(() { _purchasing = true; _error = null; });
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: _product!));
  }

  Future<void> _restore() async {
    if (_purchasing) return;
    setState(() { _purchasing = true; _error = null; });
    await _iap.restorePurchases();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unlock ResQruck'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              const Spacer(),
              Icon(Icons.shield_outlined, size: 76, color: cs.primary),
              const SizedBox(height: 20),
              Text(
                'ResQruck Full Access',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'One-time purchase unlocks all features on this device.',
                style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              ...[
                'Medical protocols & procedures',
                'Patient report documentation',
                'Tactical map with fire overlays',
                'Drug reference & dosing calculator',
                'MCI triage & decision trees',
                'Cert vault & backcountry field guide',
              ].map((f) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Icon(Icons.check_circle_rounded, color: cs.primary, size: 20),
                      const SizedBox(width: 10),
                      Text(f, style: const TextStyle(fontSize: 15)),
                    ]),
                  )),
              const Spacer(),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: TextStyle(color: cs.onErrorContainer, fontSize: 13)),
                ),
                const SizedBox(height: 12),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(),
                )
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _purchasing ? null : _buy,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _purchasing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Text(
                            _product != null
                                ? 'Buy — ${_product!.price}'
                                : 'Purchase',
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _purchasing ? null : _restore,
                    child: const Text('Restore Purchase'),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'One-time purchase • No subscription • Works offline after purchase',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
