import 'package:flutter/material.dart';

class TipsScreen extends StatelessWidget {
  const TipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.deepPurple.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to Use RMinder',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple.shade800,
                          ),
                        ),
                        Text(
                          'Tips for getting the most out of your budgeting journey',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Tips Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTipSection(
                      icon: Icons.account_balance_wallet,
                      title: '1. Set Up Your Budget',
                      tips: [
                        'Start by adding your income sources in the Budget tab',
                        'Create expense categories (e.g., Rent, Food, Transportation)',
                        'Set realistic spending limits for each category',
                        'Your total budget should not exceed your income',
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    _buildTipSection(
                      icon: Icons.list,
                      title: '2. Track Your Expenses',
                      tips: [
                        'Use the Transactions tab to record your spending',
                        'Add detailed notes to remember what you bought',
                        'Use the Filter option to find specific transactions',
                        'Review your spending patterns regularly',
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    _buildTipSection(
                      icon: Icons.attach_money,
                      title: '3. Build Your Savings',
                      tips: [
                        'Create savings goals in the Savings tab',
                        'Set realistic target amounts and timelines',
                        'Make regular contributions to stay on track',
                        'Use the "Add" and "Withdraw" buttons to manage funds',
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    _buildTipSection(
                      icon: Icons.savings,
                      title: '4. Manage Your Debts',
                      tips: [
                        'Add all your debts in the Liabilities tab',
                        'Track minimum payments and current balances',
                        'Make extra payments when possible to reduce interest',
                        'Use the payment tracking to monitor progress',
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    _buildTipSection(
                      icon: Icons.pie_chart,
                      title: '5. Review Your Progress',
                      tips: [
                        'Check the Reports tab for spending insights',
                        'Compare your actual spending to your budget',
                        'Look for areas where you can save money',
                        'Use month-end suggestions to optimize your budget',
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    _buildTipSection(
                      icon: Icons.tips_and_updates,
                      title: 'Pro Tips',
                      tips: [
                        'Amount inputs use digit-only keypad - decimal is automatic',
                        'Long-press items to access additional options',
                        'Use the Android widget for quick transaction entry',
                        'All your data stays private on your device',
                        'Carry over unspent amounts to next month for flexibility',
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Get Started Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Got It!',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipSection({
    required IconData icon,
    required String title,
    required List<String> tips,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: Colors.deepPurple.shade800,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...tips.map((tip) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 8, right: 12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade400,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    tip,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }
}