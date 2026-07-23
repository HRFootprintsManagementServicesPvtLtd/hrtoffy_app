import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/refreshable_screen.dart';
import '../widgets/skeleton_layouts.dart';
import '../widgets/app_drawer.dart';
import '../widgets/drawer_route.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/employee_ui.dart';

class EventsCalendarScreen extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const EventsCalendarScreen({
    Key? key,
    required this.email,
    required this.userData,
    required this.fetchHrmsContext,
  }) : super(key: key);

  @override
  State<EventsCalendarScreen> createState() => _EventsCalendarScreenState();
}

class _EventsCalendarScreenState extends State<EventsCalendarScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  Map<DateTime, List<dynamic>> _eventsByDate = {};
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<dynamic> _selectedEvents = [];
  bool loading = true;
  bool showEventForm = false;
  Map<String, dynamic>? editingEvent;
  late TabController _tabController;
  List<Map<String, dynamic>> createdEvents = [];
  String? _employeeId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _fetchAllEvents();
  }

  Future<void> _fetchAllEvents() async {
    setState(() => loading = true);
    try {
      final emp = await supabase.from('employee_records').select('id, organization_id').eq('email', widget.email).maybeSingle();
      if (emp == null) throw Exception("User not found");
      _employeeId = emp['id'].toString();
      final orgId = emp['organization_id'];
      final events = await supabase.from('events').select().eq('organization_id', orgId).order('event_date', ascending: true);
      Map<DateTime, List<dynamic>> byDate = {};
      for (final e in events) {
        DateTime d = DateTime.tryParse(e['event_date']) ?? DateTime.now();
        DateTime key = DateTime(d.year, d.month, d.day);
        byDate.putIfAbsent(key, () => []).add(e);
      }
      final created = (events ?? []).where((e) => (e['created_by'] ?? '').toString() == _employeeId).toList();
      setState(() {
        _eventsByDate = byDate;
        createdEvents = created.map((e) => Map<String, dynamic>.from(e)).toList();
        _selectedDay = _focusedDay;
        _selectedEvents = _eventsByDate[DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day)] ?? [];
        loading = false;
      });
    } catch (e) {
      loading = false;
    }
  }

  Widget _circleIconBtn({required String icon, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: IconButton(icon: SvgPicture.asset(icon, width: 20, height: 20, colorFilter: const ColorFilter.mode(EmployeeUi.primary, BlendMode.srcIn)), onPressed: onTap),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: EmployeeUi.pageBg,
      endDrawer: AppDrawer(
        userEmail: widget.email,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.events,
        companyLogoUrl: null,
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 140,
                floating: false,
                pinned: true,
                automaticallyImplyLeading: false,
                backgroundColor: Colors.white,
                elevation: 0,
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 12),
                    child: _circleIconBtn(
                      icon: "assets/icons/notification.svg",
                      onTap: () {
                        final empId = (widget.userData['id'] ?? widget.userData['employee_id'])?.toString() ?? '';
                        if (empId.isNotEmpty) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(employeeId: empId, userEmail: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext)));
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 16, top: 12),
                    child: _circleIconBtn(icon: "assets/icons/menu.svg", onTap: () => _scaffoldKey.currentState?.openEndDrawer()),
                  ),
                  const SizedBox(width: 1),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFEBDFF6), Colors.white],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text("Events & Meetings", style: EmployeeUi.header(24)),
                        const SizedBox(height: 4),
                        Text("Stay organized with your schedule", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: EmployeeUi.border)),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(color: EmployeeUi.primary, borderRadius: BorderRadius.circular(10)),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.black87,
                        labelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 13),
                        unselectedLabelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w500, fontSize: 13),
                        tabs: const [Tab(text: 'Calendar'), Tab(text: 'My Events')],
                      ),
                    ),
                  ],
                ),
              ),
              SliverFillRemaining(
                child: loading ? const SkeletonGoals() : TabBarView(
                  controller: _tabController,
                  children: [_buildCalendarView(), _buildCreatedEventsList()],
                ),
              ),
            ],
          ),
          if (showEventForm) EventFormModal(email: widget.email, editingEvent: editingEvent, onClose: () { setState(() { showEventForm = false; editingEvent = null; }); _fetchAllEvents(); }),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => setState(() => showEventForm = true), backgroundColor: EmployeeUi.primary, child: const Icon(Icons.add, color: Colors.white)),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 10,
        unselectedFontSize: 9,
        currentIndex: _bottomTabIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        onTap: (index) {
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.email, employeeId: _employeeId ?? ''))); return; }
          if (index == 1) { Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 3) { Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.email, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 4) { _scaffoldKey.currentState?.openEndDrawer(); return; }
        },
        items: [
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/dashboard.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Dashboard'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/leaves.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Leave'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/attendance.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Attendance'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/payroll.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'Payslip'),
          BottomNavigationBarItem(icon: SvgPicture.asset("assets/icons/menu.svg", width: 22, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)), label: 'More'),
        ],
      ),
    );
  }

  Widget _buildCalendarView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 16),
            padding: const EdgeInsets.all(10),
            decoration: EmployeeUi.cardDecoration(),
            child: TableCalendar(
              firstDay: DateTime(2020), lastDay: DateTime(2030), focusedDay: _focusedDay, selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
              calendarFormat: CalendarFormat.month, eventLoader: (day) => _eventsByDate[DateTime(day.year, day.month, day.day)] ?? [],
              onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; _selectedEvents = _eventsByDate[DateTime(sel.year, sel.month, sel.day)] ?? []; }),
              calendarStyle: const CalendarStyle(todayDecoration: BoxDecoration(color: Color(0xFFEBDFF6), shape: BoxShape.circle), selectedDecoration: BoxDecoration(color: EmployeeUi.primary, shape: BoxShape.circle), markerDecoration: BoxDecoration(color: EmployeeUi.primary, shape: BoxShape.circle)),
              headerStyle: HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
            ),
          ),
          ..._selectedEvents.map((e) => _buildEventCard(Map<String, dynamic>.from(e), false)),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildCreatedEventsList() {
    if (createdEvents.isEmpty) return Center(child: Text("No events created yet", style: GoogleFonts.montserrat(color: Colors.grey)));
    return ListView.builder(
      padding: const EdgeInsets.all(20), itemCount: createdEvents.length,
      itemBuilder: (ctx, i) => _buildEventCard(createdEvents[i], true),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event, bool showActions) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: EmployeeUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(event['title'] ?? '', style: EmployeeUi.title(15))),
            _badge(event['event_category'] ?? 'other'),
          ]),
          const SizedBox(height: 8),
          _infoRow(Icons.access_time, "${event['start_time']} - ${event['end_time']}"),
          if (event['location'] != null) _infoRow(Icons.location_on_outlined, event['location']),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [Icon(icon, size: 14, color: Colors.grey), const SizedBox(width: 8), Text(text, style: GoogleFonts.montserrat(fontSize: 12, color: Colors.black54))]));
  }

  Widget _badge(String text) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: EmployeeUi.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Text(text.toUpperCase(), style: GoogleFonts.montserrat(fontSize: 10, fontWeight: FontWeight.bold, color: EmployeeUi.primary)));
  }
}

class EventFormModal extends StatefulWidget {
  final String email; final Map<String, dynamic>? editingEvent; final VoidCallback onClose;
  const EventFormModal({Key? key, required this.email, required this.editingEvent, required this.onClose}) : super(key: key);
  @override State<EventFormModal> createState() => _EventFormModalState();
}

class _EventFormModalState extends State<EventFormModal> {
  final _formKey = GlobalKey<FormState>();
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  @override void initState() { super.initState(); if (widget.editingEvent != null) titleCtrl.text = widget.editingEvent!['title'] ?? ''; }
  @override Widget build(BuildContext context) {
    return Container(
      color: Colors.white, padding: const EdgeInsets.all(24),
      child: SafeArea(child: Form(key: _formKey, child: Column(children: [
        Row(children: [Text("Create Event", style: EmployeeUi.header(20)), const Spacer(), IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose)]),
        TextFormField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Title")),
        const Spacer(),
        ElevatedButton(onPressed: widget.onClose, style: ElevatedButton.styleFrom(backgroundColor: EmployeeUi.primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)), child: const Text("Save Event"))
      ])))
    );
  }
}
