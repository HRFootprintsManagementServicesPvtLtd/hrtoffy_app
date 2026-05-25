// lib/widgets/skeleton_layouts.dart
import 'package:flutter/material.dart';
import './skeleton.dart';
import 'package:shimmer/shimmer.dart';


// ---------------------------------------------------------
// PROFILE SKELETON
// ---------------------------------------------------------
class SkeletonProfile extends StatelessWidget {
  const SkeletonProfile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: MediaQuery.of(context).size.height,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [

          // HEADER
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: const [
              SkeletonBox(
                width: 72,
                height: 72,
                borderRadius: BorderRadius.all(Radius.circular(36)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    SkeletonBox(
                      width: double.infinity,
                      height: 16,
                      margin: EdgeInsets.only(bottom: 8),
                    ),
                    SkeletonBox(
                      width: 160,
                      height: 14,
                    ),
                  ],
                ),
              )
            ],
          ),

          const SizedBox(height: 40),

          // CARD
          const SkeletonBox(
            width: double.infinity,
            height: 150,
            margin: EdgeInsets.only(bottom: 25),
          ),

          // DETAILS
          const SkeletonBox(
            width: double.infinity,
            height: 100,
            margin: EdgeInsets.only(bottom: 8),
          ),
          const SkeletonBox(
            width: double.infinity,
            height: 116,
            margin: EdgeInsets.only(bottom: 8),
          ),

          const SizedBox(height: 20),

          const SkeletonBox(
            width: double.infinity,
            height: 140,
          ),

          const SizedBox(height: 20),

          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}



// ---------------------------------------------------------
// GENERIC LIST SKELETON (USED FOR HISTORY, LISTS, ETC.)
// ---------------------------------------------------------
class SkeletonList extends StatelessWidget {
  final int count;

  const SkeletonList({Key? key, this.count = 4}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
            (_) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: SkeletonBox(
            width: double.infinity,
            height: 64,
          ),
        ),
      ),
    );
  }
}




// ---------------------------------------------------------
// ATTENDANCE SCREEN SKELETON (FULL SCREEN)
// ---------------------------------------------------------
class SkeletonAttendance extends StatelessWidget {
  const SkeletonAttendance({super.key});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return Container(
      color: Colors.white,                 // ⭐ VERY IMPORTANT
      width: double.infinity,
      height: height,                      // FULL SCREEN
      padding: const EdgeInsets.all(16),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Top Row (clock + refresh)
          Row(
            children: const [
              SkeletonBox(width: 40, height: 40, borderRadius: BorderRadius.all(Radius.circular(20))),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(width: double.infinity, height: 16)),
              SizedBox(width: 12),
              SkeletonBox(width: 32, height: 32),
            ],
          ),

          SizedBox(height: 20),

          // Status Card
          const SkeletonBox(
            width: double.infinity,
            height: 140,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),

          SizedBox(height: 20),

          // Work Type Dropdown
          const SkeletonBox(
            width: double.infinity,
            height: 55,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),

          SizedBox(height: 20),

          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 48)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 48)),
            ],
          ),

          SizedBox(height: 25),

          const SkeletonBox(width: 150, height: 16),
          SizedBox(height: 20),

          ...List.generate(
            4,
                (_) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SkeletonBox(
                width: double.infinity,
                height: 70,
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
          ),

          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}
// ---------------------------------------------------------
// ANNOUNCEMENTS SKELETON
class SkeletonAnnouncements extends StatelessWidget {
  const SkeletonAnnouncements({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonBox(width: double.infinity, height: 120, margin: EdgeInsets.only(bottom: 16)),
          SkeletonBox(width: double.infinity, height: 120, margin: EdgeInsets.only(bottom: 16)),
          SkeletonBox(width: double.infinity, height: 120, margin: EdgeInsets.only(bottom: 16)),
          SkeletonBox(width: double.infinity, height: 120, margin: EdgeInsets.only(bottom: 16)),
          SkeletonBox(width: double.infinity, height: 120, margin: EdgeInsets.only(bottom: 16)),
          SizedBox(height: 300), // fill space to avoid blank
        ],
      ),
    );
  }
}
//benifits skeleton
class SkeletonBenefits extends StatelessWidget {
  const SkeletonBenefits({super.key});

  Widget _item() {
    return Container(
      height: 120,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      width: double.infinity,
      height: MediaQuery.of(context).size.height, // ⭐ FIX: full height, NOT infinite
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // ⭐ DO NOT USE SCROLL HERE.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _item(),
                _item(),
                _item(),
                _item(),
                _item(),
                _item(),
              ],
            ),
          ),

          const Spacer(), // ⭐ Fills space, prevents infinite height
        ],
      ),
    );
  }
}
// ---------------------------------------------------------
// LEAVES — SUMMARY PAGE (GRID + POLICY LIST)
// ---------------------------------------------------------
class SkeletonLeaveSummaryPage extends StatelessWidget {
  const SkeletonLeaveSummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Use SingleChildScrollView to avoid nesting ListViews
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 7 Summary Cards (Wrap so it adapts to width)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(
              7,
                  (_) => const SkeletonBox(
                width: 165,
                height: 80,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SkeletonBox(width: 200, height: 18),
          const SizedBox(height: 12),
          // Policy cards
          Column(
            children: List.generate(
              5,
                  (_) => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: SkeletonBox(
                  width: double.infinity,
                  height: 70,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// LEAVES — CALENDAR PAGE
// ---------------------------------------------------------
class SkeletonLeaveCalendar extends StatelessWidget {
  const SkeletonLeaveCalendar({super.key});

  @override
  Widget build(BuildContext context) {
    // Avoid using Expanded inside an unbounded parent.
    // Build calendar-like grid using Wrap/Column with fixed sizes.
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Simulated calendar grid using rows of small boxes
          Column(
            children: List.generate(6, (rowIdx) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (colIdx) {
                    return const SkeletonBox(width: 42, height: 42);
                  }),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          // Selected day's events skeleton
          Column(
            children: List.generate(
              3,
                  (_) => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: SkeletonBox(
                  width: double.infinity,
                  height: 70,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// LEAVES — APPLY LEAVE FORM
// ---------------------------------------------------------
class SkeletonLeaveApplicationForm extends StatelessWidget {
  const SkeletonLeaveApplicationForm({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: const [
          SkeletonBox(height: 55), // Leave type dropdown
          SizedBox(height: 14),
          SkeletonBox(height: 55), // From Date
          SizedBox(height: 14),
          SkeletonBox(height: 55), // To Date
          SizedBox(height: 14),
          SkeletonBox(height: 80), // Reason textfield
          SizedBox(height: 20),
          SkeletonBox(height: 48), // Submit button
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// LEAVES — HISTORY PAGE
// ---------------------------------------------------------
class SkeletonLeaveHistory extends StatelessWidget {
  const SkeletonLeaveHistory({super.key});

  @override
  Widget build(BuildContext context) {
    // Use Column + SizedBoxes so it's safe in any ancestor
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          7,
              (_) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: SkeletonBox(
              width: double.infinity,
              height: 110,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// LEAVES — MAIN SCREEN (AppBar + Main Tabs + Sub Tabs)
// ---------------------------------------------------------
// This is an optional combined skeleton you can show as a top-level placeholder
class SkeletonLeavesMain extends StatelessWidget {
  const SkeletonLeavesMain({super.key});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // APPBAR Title
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                alignment: Alignment.centerLeft,
                child: const SkeletonBox(width: 180, height: 20),
              ),
              // Main Tabs
              SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: const [
                    SkeletonBox(width: 140, height: 30),
                    SkeletonBox(width: 140, height: 30),
                  ],
                ),
              ),
              // Sub Tabs
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: const [
                    SkeletonBox(width: 140, height: 28),
                    SizedBox(width: 12),
                    SkeletonBox(width: 140, height: 28),
                  ],
                ),
              ),
              // Body - default to summary skeleton
              const SizedBox(height: 12),
              const SkeletonLeaveSummaryPage(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------------------------------------------------
// OVERTIME — RECORDS LIST SKELETON
// ---------------------------------------------------------
class SkeletonOTRecords extends StatelessWidget {
  const SkeletonOTRecords({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: SkeletonBox(
          width: double.infinity,
          height: 120,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
    );
  }
}
// ---------------------------------------------------------
// PAYSLIPS — FULL PAGE SKELETON
// ---------------------------------------------------------
class SkeletonPayslipPage extends StatelessWidget {
  const SkeletonPayslipPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Heading text
          const SkeletonBox(width: 220, height: 18, margin: EdgeInsets.only(bottom: 16)),

          // Employee Info Card
          _cardSkeleton(height: 150),

          const SizedBox(height: 16),

          // Period Selector Card
          _cardSkeleton(height: 160),

          const SizedBox(height: 16),

          // Payslip Card
          _payslipCardSkeleton(),
        ],
      ),
    );
  }

  // Generic card skeleton box
  static Widget _cardSkeleton({required double height}) {
    return SkeletonBox(
      width: double.infinity,
      height: height,
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );
  }

  // Detailed payslip card skeleton
  static Widget _payslipCardSkeleton() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: const [
          // Payslip Header
          SkeletonBox(width: double.infinity, height: 24, margin: EdgeInsets.only(bottom: 18)),

          // Company + Location
          SkeletonBox(width: 200, height: 16, margin: EdgeInsets.only(bottom: 12)),
          SkeletonBox(width: 120, height: 14, margin: EdgeInsets.only(bottom: 18)),

          // Information rows
          SkeletonBox(width: double.infinity, height: 14, margin: EdgeInsets.only(bottom: 10)),
          SkeletonBox(width: double.infinity, height: 14, margin: EdgeInsets.only(bottom: 10)),
          SkeletonBox(width: double.infinity, height: 14, margin: EdgeInsets.only(bottom: 10)),
          SkeletonBox(width: double.infinity, height: 14, margin: EdgeInsets.only(bottom: 10)),
          SkeletonBox(width: double.infinity, height: 14, margin: EdgeInsets.only(bottom: 10)),
          SkeletonBox(width: double.infinity, height: 14, margin: EdgeInsets.only(bottom: 10)),
          SkeletonBox(width: double.infinity, height: 14, margin: EdgeInsets.only(bottom: 10)),

          // Earnings Card
          SizedBox(height: 20),
          SkeletonBox(width: double.infinity, height: 180),

          SizedBox(height: 20),

          // Deductions Card
          SkeletonBox(width: double.infinity, height: 180),

          SizedBox(height: 20),

          // Net Pay
          SkeletonBox(width: double.infinity, height: 80),
        ],
      ),
    );
  }
}
// ---------------------------------------------------------
// LOANS — MY LOANS SKELETON (Announcements-style cards)
// ---------------------------------------------------------
class SkeletonLoansMyLoans extends StatelessWidget {
  const SkeletonLoansMyLoans({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(width: 140, height: 16),
            SizedBox(height: 10),
            SkeletonBox(width: 220, height: 14),
            SizedBox(height: 8),
            SkeletonBox(width: 180, height: 14),
            SizedBox(height: 8),
            SkeletonBox(width: 160, height: 14),
          ],
        ),
      ),
    );
  }
}
// ---------------------------------------------------------
// LOANS — APPLY FOR LOAN FORM SKELETON
// ---------------------------------------------------------
class SkeletonLoansApplyForm extends StatelessWidget {
  const SkeletonLoansApplyForm({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBox(height: 55), // Utilization Bar
        SizedBox(height: 18),

        SkeletonBox(height: 55), // Loan Category
        SizedBox(height: 14),

        SkeletonBox(height: 55), // Requested Amount
        SizedBox(height: 14),

        SkeletonBox(height: 55), // Tenure Dropdown
        SizedBox(height: 14),

        SkeletonBox(height: 55), // EMI Start Date
        SizedBox(height: 14),

        SkeletonBox(height: 80), // Purpose Field
        SizedBox(height: 20),

        SkeletonBox(height: 48), // Submit Button
      ],
    );
  }
}
// ---------------------------------------------------------
// LOANS — EMI SCHEDULE SKELETON (Simple list items)
// ---------------------------------------------------------
class SkeletonLoansEMISchedule extends StatelessWidget {
  const SkeletonLoansEMISchedule({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: SkeletonBox(
          width: double.infinity,
          height: 90,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}
class SkeletonTravelClaimsList extends StatelessWidget {
  const SkeletonTravelClaimsList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(4, (index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(height: 14, width: 120, color: Colors.grey.shade300),
                  const Spacer(),
                  Container(height: 20, width: 60, color: Colors.grey.shade300),
                ],
              ),
              const SizedBox(height: 10),
              Container(height: 12, width: 160, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Container(height: 12, width: double.infinity, color: Colors.grey.shade300),
              const SizedBox(height: 5),
              Container(height: 12, width: 100, color: Colors.grey.shade300),
            ],
          ),
        );
      }),
    );
  }
}
class SkeletonTravelClaimForm extends StatelessWidget {
  const SkeletonTravelClaimForm();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(height: 20, width: 200, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          ...List.generate(5, (index) {
            return Container(
              height: 50,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
            );
          }),
          const SizedBox(height: 16),
          Container(height: 45, width: double.infinity, color: Colors.grey.shade300),
        ],
      ),
    );
  }
}
class SkeletonTravelClaimDetails extends StatelessWidget {
  const SkeletonTravelClaimDetails();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 20, width: 200, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          Container(height: 14, width: 150, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Container(height: 14, width: 220, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Container(height: 14, width: 180, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Container(height: 14, width: 140, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          ...List.generate(4, (index) {
            return Container(
              height: 60,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.grey.shade200,
              ),
            );
          }),
        ],
      ),
    );
  }
}
// ---------------------------------------------------------
// TAX DECLARATION — FULL PAGE SKELETON
// ---------------------------------------------------------
class SkeletonTaxDeclarationPage extends StatelessWidget {
  const SkeletonTaxDeclarationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Employee info card
          const SkeletonBox(
            width: double.infinity,
            height: 110,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            margin: EdgeInsets.only(bottom: 16),
          ),

          // Regime selection card
          const SkeletonBox(
            width: double.infinity,
            height: 150,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            margin: EdgeInsets.only(bottom: 16),
          ),

          // Tax summary card
          const SkeletonBox(
            width: double.infinity,
            height: 200,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            margin: EdgeInsets.only(bottom: 16),
          ),

          // Deductions list (old regime only)
          Column(
            children: List.generate(
              4,
                  (_) => const SkeletonBox(
                width: double.infinity,
                height: 120,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                margin: EdgeInsets.only(bottom: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
//Skeleton

Widget eventsCalendarSkeleton() {
  return Padding(

    padding: const EdgeInsets.all(16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        SizedBox(height: 20),
        Container(
          height: 20,
          width: 220,
          color: Colors.grey.shade300,
        ),
        SizedBox(height: 10),
        ListView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: 3,
          itemBuilder: (_, __) => Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        )
      ],
    ),
  );
}
Widget eventsCreatedSkeleton() {
  return ListView.builder(
    padding: EdgeInsets.all(16),
    itemCount: 5,
    itemBuilder: (_, __) => Container(
      height: 70,
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );
}
// ---------------- Surveys Skeleton ----------------

Widget surveysListSkeleton() {
  return ListView.separated(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    itemCount: 6,
    separatorBuilder: (_, __) => const SizedBox(height: 16),
    itemBuilder: (_, __) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 18,
            width: 160,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 10),
          Container(
            height: 14,
            width: 220,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(height: 14, width: 80, color: Colors.grey.shade300),
              const SizedBox(width: 20),
              Container(height: 14, width: 80, color: Colors.grey.shade300),
            ],
          ),
        ],
      ),
    ),
  );
}
// --- FAQ SKELETONS ---

Widget faqSearchSkeleton() {
  return Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget faqCategorySkeleton() {
  return Card(
    margin: const EdgeInsets.only(bottom: 20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Container(
                width: 150,
                height: 18,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 8),
              Container(
                width: 80,
                height: 20,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Repeated FAQ question blocks
          ...List.generate(
            3,
                (i) => Padding(
              padding: const EdgeInsets.only(bottom: 18.0),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(6),
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
//Dashboard welcome
Widget dashboardWelcomeSkeleton() {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 18, width: 180, color: Colors.grey.shade300),
        const SizedBox(height: 6),
        Container(height: 14, width: 120, color: Colors.grey.shade300),
        const SizedBox(height: 14),
        Container(height: 16, width: 150, color: Colors.grey.shade300),
        const SizedBox(height: 6),
        Container(height: 14, width: 140, color: Colors.grey.shade300),
        Container(height: 14, width: 160, color: Colors.grey.shade300),
        const SizedBox(height: 10),
        Container(height: 12, width: 180, color: Colors.grey.shade300),
        Container(height: 12, width: 150, color: Colors.grey.shade300),
        Container(height: 12, width: 160, color: Colors.grey.shade300),
      ],
    ),
  );
}
//dashboard manager
Widget dashboardManagerSkeleton() {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 16, width: 190, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        ...List.generate(2, (_) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  height: 22,
                  width: 22,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Container(
                        height: 14, color: Colors.grey.shade300)),
              ],
            ),
          );
        }),
      ],
    ),
  );
}
//dashboard attendance
Widget dashboardAttendanceSkeleton() {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 16, width: 150, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        Container(height: 14, width: 120, color: Colors.grey.shade300),
        const SizedBox(height: 18),
        Container(height: 12, width: 120, color: Colors.grey.shade300),
        const SizedBox(height: 18),
        Container(height: 12, width: 120, color: Colors.grey.shade300),
        const SizedBox(height: 18),

        // Work type skeleton row
        Container(height: 50, width: double.infinity, color: Colors.grey.shade300),
        const SizedBox(height: 12),

        // Punch buttons
        Row(
          children: [
            Expanded(child: Container(height: 45, color: Colors.grey.shade300)),
            const SizedBox(width: 12),
            Expanded(child: Container(height: 45, color: Colors.grey.shade300)),
          ],
        ),
      ],
    ),
  );
}
/// 🔵 Single notification skeleton card
Widget notificationSkeletonCard() {
  return Shimmer.fromColors(
    baseColor: Colors.grey.shade300,
    highlightColor: Colors.grey.shade100,
    child: Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon placeholder
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),

          // Text lines
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title line
                Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle line
                Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),

                // Time line
                Container(
                  height: 10,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 🔵 List of skeleton cards
Widget notificationsSkeletonList() {
  return ListView.builder(
    padding: const EdgeInsets.only(top: 10),
    itemCount: 8,
    itemBuilder: (context, index) => notificationSkeletonCard(),
  );
}
// ---------------------------------------------------------
// GOALS SCREEN SKELETON
// ---------------------------------------------------------

class SkeletonGoals extends StatelessWidget {
  const SkeletonGoals({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: 5,
      itemBuilder: (_, __) {
        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(18),

          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(24),
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Title
              Container(
                height: 24,
                width: 220,
                color: Colors.grey.shade300,
              ),

              const SizedBox(height: 16),

              // Chips
              Row(
                children: [
                  Container(
                    height: 30,
                    width: 80,
                    color: Colors.grey.shade300,
                  ),

                  const SizedBox(width: 10),

                  Container(
                    height: 30,
                    width: 90,
                    color: Colors.grey.shade300,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Description lines
              Container(
                height: 14,
                width: double.infinity,
                color: Colors.grey.shade300,
              ),

              const SizedBox(height: 8),

              Container(
                height: 14,
                width: double.infinity,
                color: Colors.grey.shade300,
              ),

              const SizedBox(height: 20),

              // Progress bar
              Container(
                height: 10,
                width: double.infinity,
                color: Colors.grey.shade300,
              ),

              const SizedBox(height: 24),

              // Milestones
              ...List.generate(
                3,
                    (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    height: 14,
                    width: double.infinity,
                    color: Colors.grey.shade300,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------
// MESSAGES SKELETON
// ---------------------------------------------------------

class SkeletonMessages extends StatelessWidget {

  const SkeletonMessages({
    super.key,
  });

  @override
  Widget build(BuildContext context) {

    return ListView.builder(

      padding:
      const EdgeInsets.all(16),

      itemCount: 8,

      itemBuilder: (_, index) {

        return Container(

          margin:
          const EdgeInsets.only(
            bottom: 14,
          ),

          padding:
          const EdgeInsets.all(14),

          decoration: BoxDecoration(

            color:
            Colors.grey.shade200,

            borderRadius:
            BorderRadius.circular(
              20,
            ),
          ),

          child: Row(

            children: [

              CircleAvatar(
                radius: 28,
                backgroundColor:
                Colors.grey.shade300,
              ),

              const SizedBox(
                width: 14,
              ),

              Expanded(

                child: Column(

                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,

                  children: [

                    Container(

                      height: 16,

                      width: 120,

                      decoration:
                      BoxDecoration(

                        color: Colors
                            .grey
                            .shade300,

                        borderRadius:
                        BorderRadius
                            .circular(
                          4,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    Container(

                      height: 12,

                      width: 180,

                      decoration:
                      BoxDecoration(

                        color: Colors
                            .grey
                            .shade300,

                        borderRadius:
                        BorderRadius
                            .circular(
                          4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Container(

                height: 12,

                width: 40,

                decoration:
                BoxDecoration(

                  color:
                  Colors.grey
                      .shade300,

                  borderRadius:
                  BorderRadius
                      .circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}