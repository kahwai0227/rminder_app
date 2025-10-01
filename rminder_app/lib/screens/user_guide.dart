import 'package:flutter/material.dart';

Future<void> showUserGuide(BuildContext context) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _UserGuideDialog(),
  );
}

class _UserGuideDialog extends StatefulWidget {
  const _UserGuideDialog();
  @override
  State<_UserGuideDialog> createState() => _UserGuideDialogState();
}

class _UserGuideDialogState extends State<_UserGuideDialog> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _pages.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_index > 0) {
      _controller.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  List<_GuidePage> get _pages => [
        _GuidePage(
          icon: Icons.account_balance_wallet,
          title: 'Budget',
          bullets: const [
            'Set monthly limits for your categories',
            'See how much you have left to spend',
          ],
        ),
        _GuidePage(
          icon: Icons.list,
          title: 'Transactions',
          bullets: const [
            'Add and edit spending entries',
            'Filter by category, amount, or date',
          ],
        ),
        _GuidePage(
          icon: Icons.attach_money,
          title: 'Savings (Sinking funds)',
          bullets: const [
            'Plan and track savings goals',
            'Contribute (+) or spend (-) from a fund',
          ],
        ),
        _GuidePage(
          icon: Icons.savings,
          title: 'Liabilities',
          bullets: const [
            'Track balances and minimum payments',
            'Log payments and optional extra amounts',
          ],
        ),
        _GuidePage(
          icon: Icons.pie_chart,
          title: 'Reports & Periods',
          bullets: const [
            'Review spending for the active period',
            'Use the menu to “Close period” when you’re ready',
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Welcome to RMinder'),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _pages.length,
                itemBuilder: (ctx, i) => _GuidePageView(page: _pages[i]),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _index == 0 ? null : _prev, child: const Text('Previous')),
        ElevatedButton(onPressed: _next, child: Text(_index == _pages.length - 1 ? 'Done' : 'Next')),
      ],
    );
  }
}

class _GuidePage {
  final IconData icon;
  final String title;
  final List<String> bullets;
  const _GuidePage({required this.icon, required this.title, required this.bullets});
}

class _GuidePageView extends StatelessWidget {
  final _GuidePage page;
  const _GuidePageView({required this.page});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(page.icon, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text(page.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ...page.bullets.map((b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Flexible(child: Text(b, textAlign: TextAlign.center)),
                ],
              ),
            )),
      ],
    );
  }
}
