import 'package:flutter/material.dart';
import 'models/models.dart' as models;

class BudgetCategoryExpansionPanel extends StatefulWidget {
  final List<models.BudgetCategory> categories;
  final Function(models.BudgetCategory) onEdit;
  final Function(models.BudgetCategory) onDelete;
  const BudgetCategoryExpansionPanel({
    required this.categories,
    required this.onEdit,
    required this.onDelete,
    Key? key,
  }) : super(key: key);

  @override
  State<BudgetCategoryExpansionPanel> createState() => _BudgetCategoryExpansionPanelState();
}

class _BudgetCategoryExpansionPanelState extends State<BudgetCategoryExpansionPanel> {
  List<bool> _expanded = [];

  @override
  void didUpdateWidget(covariant BudgetCategoryExpansionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.categories.length != _expanded.length) {
      _expanded = List.generate(widget.categories.length, (i) => false);
    }
  }

  @override
  void initState() {
    super.initState();
    _expanded = List.generate(widget.categories.length, (i) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.categories.isEmpty) return Center(child: Text('No budget categories yet.'));
    return ExpansionPanelList(
      expansionCallback: (int index, bool isExpanded) {
        setState(() {
          _expanded[index] = !isExpanded;
        });
      },
      children: List.generate(widget.categories.length, (index) {
        final category = widget.categories[index];
        return ExpansionPanel(
          canTapOnHeader: true,
          isExpanded: _expanded[index],
          headerBuilder: (context, isExpanded) {
            return ListTile(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(category.name),
                  Text('Limit: ₹${category.budgetLimit.toStringAsFixed(2)}', style: TextStyle(color: Colors.blue)),
                ],
              ),
            );
          },
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Spent', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          Text('₹${category.spent.toStringAsFixed(2)}', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Remain', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          Text('₹${(category.budgetLimit - category.spent).toStringAsFixed(2)}', style: TextStyle(color: Colors.green)),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => widget.onEdit(category),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete, color: Colors.red),
                      onPressed: () => widget.onDelete(category),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
