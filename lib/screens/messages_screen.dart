import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat_conversation.dart';
import '../services/chat_service.dart';
import 'chat_thread_screen.dart';
import '../widgets/new_chat_dialog.dart';
import '../widgets/create_channel_dialog.dart';
import '../widgets/app_drawer.dart';
import '../widgets/drawer_route.dart';
import '../widgets/skeleton_layouts.dart';
import 'dashboard_screen.dart';
import 'leaves_screen.dart';
import 'attendance_screen.dart';
import 'payslip_screen.dart';
import 'notification.dart';
import '../widgets/employee_ui.dart';

class MessagesScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function() fetchHrmsContext;

  const MessagesScreen({
    super.key,
    required this.userEmail,
    required this.userData,
    required this.fetchHrmsContext,
  });

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final ChatService chatService = ChatService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bottomTabIndex = 0;
  bool loading = true;
  List<ChatConversation> conversations = [];

  @override
  void initState() {
    super.initState();
    loadChats();
  }

  Future<void> loadChats() async {
    try {
      final result = await chatService.loadConversations();
      setState(() { conversations = result; loading = false; });
    } catch (e) {
      debugPrint(e.toString());
      setState(() { loading = false; });
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
        userEmail: widget.userEmail,
        userData: widget.userData,
        fetchHrmsContext: widget.fetchHrmsContext,
        currentRoute: DrawerRoute.messages,
        companyLogoUrl: null,
      ),
      body: CustomScrollView(
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
                      Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(employeeId: empId, userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext)));
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
                    colors: [Color(0xFFD7E8FF), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("Messages", style: EmployeeUi.header(24)),
                    const SizedBox(height: 4),
                    Text("Connect with your colleagues", style: GoogleFonts.montserrat(fontSize: 12, color: EmployeeUi.muted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: loading ? const SkeletonMessages() : Padding(
              padding: const EdgeInsets.all(20),
              child: conversations.isEmpty
                  ? Center(child: Text("No conversations yet.", style: GoogleFonts.montserrat(color: Colors.grey)))
                  : Column(children: conversations.map((c) => _buildConversationCard(c)).toList()),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            builder: (_) => SafeArea(child: Wrap(children: [
              ListTile(leading: const Icon(Icons.person), title: const Text("New Direct Message"), onTap: () { Navigator.pop(context); showDialog(context: context, builder: (_) => NewChatDialog(onCreated: loadChats)); }),
              ListTile(leading: const Icon(Icons.group), title: const Text("Create Group Channel"), onTap: () { Navigator.pop(context); showDialog(context: context, builder: (_) => CreateChannelDialog(onCreated: loadChats)); }),
            ])),
          );
        },
        backgroundColor: EmployeeUi.primary,
        child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
      ),
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
          if (index == 0) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(email: widget.userEmail, employeeId: widget.userData['id']))); return; }
          if (index == 1) { Navigator.push(context, MaterialPageRoute(builder: (_) => LeavesScreen(email: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => TimeAttendanceScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
          if (index == 3) { Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipScreen(userEmail: widget.userEmail, userData: widget.userData, fetchHrmsContext: widget.fetchHrmsContext))); return; }
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

  Widget _buildConversationCard(ChatConversation c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: EmployeeUi.cardDecoration(),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(radius: 24, backgroundColor: const Color(0xFFD7E8FF), child: Text(c.title.isNotEmpty ? c.title[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.bold, color: EmployeeUi.primary))),
        title: Text(c.title, style: EmployeeUi.title(15)),
        subtitle: Text(c.latestMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.montserrat(fontSize: 13, color: Colors.black54)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThreadScreen(channelId: c.id, title: c.title))),
      ),
    );
  }
}
