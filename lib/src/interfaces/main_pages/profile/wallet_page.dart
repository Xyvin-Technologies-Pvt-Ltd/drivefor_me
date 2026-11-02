import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/wallet_model.dart';
import 'package:DriveForme/src/data/providers/wallet_provider.dart';
import 'package:DriveForme/src/interfaces/main_pages/profile/wallet_recharge_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum _WalletTxFilter { all, credit, debit }

class _WalletDayGroup {
  final DateTime date;
  final List<WalletTransaction> transactions;

  const _WalletDayGroup({required this.date, required this.transactions});

  double get dayNetTotal => transactions.fold<double>(
    0,
    (sum, tx) => sum + (tx.isCredit ? tx.amount : -tx.amount),
  );

  String get headerDate => DateFormat('EEE, d MMM').format(date);

  String get headerAmount {
    final prefix = dayNetTotal >= 0 ? '' : '-';
    return '$prefix₹${dayNetTotal.abs().toStringAsFixed(3)}';
  }
}

class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key});

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage> {
  _WalletTxFilter _filter = _WalletTxFilter.all;

  List<WalletTransaction> _filteredTransactions(List<WalletTransaction> items) {
    switch (_filter) {
      case _WalletTxFilter.credit:
        return items.where((tx) => tx.isCredit).toList();
      case _WalletTxFilter.debit:
        return items.where((tx) => !tx.isCredit).toList();
      case _WalletTxFilter.all:
        return items;
    }
  }

  List<_WalletDayGroup> _groupByDay(List<WalletTransaction> transactions) {
    final sorted = [...transactions]
      ..sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });

    final grouped = <DateTime, List<WalletTransaction>>{};
    for (final tx in sorted) {
      final createdAt = tx.createdAt;
      if (createdAt == null) continue;
      final key = DateTime(createdAt.year, createdAt.month, createdAt.day);
      grouped.putIfAbsent(key, () => []).add(tx);
    }

    return grouped.entries
        .map(
          (entry) =>
              _WalletDayGroup(date: entry.key, transactions: entry.value),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _showFilterSheet() async {
    final selected = await showModalBottomSheet<_WalletTxFilter>(
      context: context,
      backgroundColor: kWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Filter transactions', style: kWalletSectionTitleSB),
              const SizedBox(height: 12),
              _FilterOption(
                label: 'All transactions',
                selected: _filter == _WalletTxFilter.all,
                onTap: () => Navigator.pop(context, _WalletTxFilter.all),
              ),
              _FilterOption(
                label: 'Credits only',
                selected: _filter == _WalletTxFilter.credit,
                onTap: () => Navigator.pop(context, _WalletTxFilter.credit),
              ),
              _FilterOption(
                label: 'Debits only',
                selected: _filter == _WalletTxFilter.debit,
                onTap: () => Navigator.pop(context, _WalletTxFilter.debit),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null) setState(() => _filter = selected);
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor: kWhite,
      appBar: AppBar(
        backgroundColor: kWhite,
        surfaceTintColor: kWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: kReferEarnPaddingH - 8),
          child: Center(
            child: _RoundIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        title: Text('Wallet', style: kWalletAppBarSB),
      ),
      body: walletAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: kStyle(kRegular, kSize14, color: kMutedText),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.invalidate(walletProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (wallet) {
          final filtered = _filteredTransactions(wallet.transactions);
          final groups = _groupByDay(filtered);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(walletProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                kReferEarnPaddingH,
                8,
                kReferEarnPaddingH,
                24,
              ),
              children: [
                _BalanceCard(
                  balance: wallet.displayBalanceDetailed,
                  onAddBalance: () => WalletRechargeSheet.show(context),
                ),
                const SizedBox(height: 24),
                _TransactionsHeader(onFilterTap: _showFilterSheet),
                const SizedBox(height: 12),
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'No transactions yet.',
                      textAlign: TextAlign.center,
                      style: kStyle(kRegular, kSize14, color: kMutedText),
                    ),
                  )
                else
                  ...groups.expand(
                    (group) => [
                      _DateHeader(
                        dateLabel: group.headerDate,
                        amountLabel: group.headerAmount,
                      ),
                      ...group.transactions.map(
                        (tx) => _TransactionRow(transaction: tx),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RoundIconButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kReferBackBtnBg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.chevron_left_rounded, size: 26, color: kTextColor),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final String balance;
  final VoidCallback onAddBalance;

  const _BalanceCard({required this.balance, required this.onAddBalance});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kCardRadiusSm),
        border: Border.all(color: kWalletCardBorder),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kWalletCardBgStart, kWalletCardBgEnd],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Available Balance', style: kWalletBalanceLabelR),
                const SizedBox(height: 8),
                Text(balance, style: kWalletBalanceAmountSB),
                const SizedBox(height: 12),
                Material(
                  color: kWalletBalanceGold,
                  borderRadius: BorderRadius.circular(30),
                  child: InkWell(
                    onTap: onAddBalance,
                    borderRadius: BorderRadius.circular(30),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, color: kWhite, size: 15),
                          const SizedBox(width: 3),
                          Text(
                            'Add Balance',
                            style: kStyle(
                              kMedium,
                              kSize12,
                              color: kWhite,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Image.asset(
            'assets/pngs/wallet_image.png',
            width: 96,
            height: 88,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}

class _TransactionsHeader extends StatelessWidget {
  final VoidCallback onFilterTap;

  const _TransactionsHeader({required this.onFilterTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('All Transactions', style: kWalletSectionTitleSB)),
        Material(
          color: kReferBackBtnBg,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onFilterTap,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.tune_rounded, size: 20, color: kTextColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateHeader extends StatelessWidget {
  final String dateLabel;
  final String amountLabel;

  const _DateHeader({required this.dateLabel, required this.amountLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: kWalletDateHeaderBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(dateLabel, style: kWalletDateHeaderR)),
          Text(amountLabel, style: kWalletDateHeaderR),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final WalletTransaction transaction;

  const _TransactionRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TransactionIcon(transaction: transaction),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(transaction.displayTitle, style: kWalletTxTitleSB),
                const SizedBox(height: 4),
                Text(transaction.walletListDate, style: kWalletTxSubtitleR),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            transaction.isCredit
                ? transaction.walletCreditAmount
                : transaction.walletDebitAmount,
            style: transaction.isCredit ? kWalletTxCreditSB : kWalletTxDebitSB,
          ),
        ],
      ),
    );
  }
}

class _TransactionIcon extends StatelessWidget {
  final WalletTransaction transaction;

  const _TransactionIcon({required this.transaction});

  @override
  Widget build(BuildContext context) {
    if (transaction.isReferralTransaction) {
      return Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: kActiveGreen,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.swap_horiz_rounded, color: kWhite, size: 22),
      );
    }

    return SizedBox(
      width: 40,
      height: 40,
      child: Icon(
        transaction.isRideTransaction
            ? Icons.directions_car_outlined
            : Icons.receipt_long_outlined,
        color: kTextColor,
        size: 26,
      ),
    );
  }
}

class _FilterOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: kWalletTxTitleSB),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: kBrandBlue, size: 22)
          : null,
      onTap: onTap,
    );
  }
}
