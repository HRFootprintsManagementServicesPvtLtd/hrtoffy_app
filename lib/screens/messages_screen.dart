import 'package:flutter/material.dart';

import '../models/chat_conversation.dart';

import '../services/chat_service.dart';

import 'chat_thread_screen.dart';

import '../widgets/new_chat_dialog.dart';

import '../widgets/create_channel_dialog.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../widgets/app_drawer.dart';

import '../widgets/drawer_route.dart';

import '../widgets/skeleton_layouts.dart';

import 'dashboard_screen.dart';

import 'leaves_screen.dart';

import 'attendance_screen.dart';

import 'payslip_screen.dart';


final GlobalKey<ScaffoldState>
_scaffoldKey =
GlobalKey<ScaffoldState>();

int _bottomTabIndex = 4;

class MessagesScreen extends StatefulWidget {

  final String userEmail;

  final Map<String, dynamic> userData;

  final Future<Map<String, dynamic>>
  Function() fetchHrmsContext;

  const MessagesScreen({

    super.key,

    required this.userEmail,

    required this.userData,

    required this.fetchHrmsContext,
  });

  @override
  State<MessagesScreen> createState() =>
      _MessagesScreenState();
}

class _MessagesScreenState
    extends State<MessagesScreen> {

  final ChatService chatService =
  ChatService();

  bool loading = true;

  List<ChatConversation>
  conversations = [];

  @override
  void initState() {

    super.initState();

    loadChats();
  }

  Future<void> loadChats() async {

    try {

      final result =
      await chatService
          .loadConversations();

      setState(() {

        conversations = result;

        loading = false;
      });

    } catch (e) {

      debugPrint(e.toString());

      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      key: _scaffoldKey,

      backgroundColor: Colors.white,

      endDrawer: AppDrawer(

        userEmail: widget.userEmail,

        userData: widget.userData,

        fetchHrmsContext:
        widget.fetchHrmsContext,

        currentRoute:
        DrawerRoute.messages,

        companyLogoUrl: null,
      ),

      appBar: AppBar(

        elevation: 0,

        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        title: const Text(

          "Messages",

          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),

        actions: [

          // + BUTTON
          IconButton(

            onPressed: () {

              showModalBottomSheet(

                context: context,

                backgroundColor: Colors.white,

                shape:
                const RoundedRectangleBorder(

                  borderRadius:
                  BorderRadius.vertical(

                    top: Radius.circular(24),
                  ),
                ),

                builder: (_) {

                  return SafeArea(

                    child: Wrap(

                      children: [

                        ListTile(

                          leading: const Icon(
                            Icons.person,
                          ),

                          title: const Text(
                            "New Direct Message",
                          ),

                          onTap: () {

                            Navigator.pop(context);

                            showDialog(

                              context: context,

                              builder: (_) =>
                                  NewChatDialog(

                                    onCreated:
                                    loadChats,
                                  ),
                            );
                          },
                        ),

                        ListTile(

                          leading: const Icon(
                            Icons.group,
                          ),

                          title: const Text(
                            "Create Group Channel",
                          ),

                          onTap: () {

                            Navigator.pop(context);

                            showDialog(

                              context: context,

                              builder: (_) =>
                                  CreateChannelDialog(

                                    onCreated:
                                    loadChats,
                                  ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },

            icon: const Icon(
              Icons.add,
              color: Colors.black,
            ),
          ),

          // MENU BUTTON
          IconButton(

            onPressed: () {

              _scaffoldKey.currentState
                  ?.openEndDrawer();
            },

            icon: const Icon(
              Icons.menu,
              color: Colors.black,
            ),
          ),
        ],
      ),

      body: loading

          ? const SkeletonMessages()

          : conversations.isEmpty

          ? const Center(
        child: Text(
          "No conversations",
        ),
      )

          : ListView.separated(

        padding:
        const EdgeInsets.all(16),

        itemCount:
        conversations.length,

        separatorBuilder:
            (_, __) =>
        const SizedBox(
          height: 14,
        ),

        itemBuilder:
            (context, index) {

          final conversation =
          conversations[index];

          String time = '';

          if (conversation
              .latestTime !=
              null) {

            time =
                TimeOfDay.fromDateTime(

                  conversation
                      .latestTime!
                      .toLocal(),

                ).format(context);
          }

          return InkWell(

            borderRadius:
            BorderRadius.circular(
              20,
            ),

            onTap: () {

              Navigator.push(

                context,

                MaterialPageRoute(

                  builder: (_) => ChatThreadScreen(

                    channelId: conversation.id,

                    title: conversation.title,
                  ),
                ),
              );
            },

            child: Container(

              padding:
              const EdgeInsets.all(
                14,
              ),

              decoration:
              BoxDecoration(

                color:
                Colors.white,

                borderRadius:
                BorderRadius.circular(
                  20,
                ),

                border: Border.all(
                  color:
                  Colors.grey.shade200,
                ),
              ),

              child: Row(

                children: [

                  CircleAvatar(

                    radius: 28,

                    backgroundColor:
                    const Color(
                      0xFFD9EBFF,
                    ),

                    child: Text(

                      (conversation.title.isNotEmpty
                          ? conversation.title[0]
                          : '?')
                          .toUpperCase(),

                      style:
                      const TextStyle(

                        fontWeight:
                        FontWeight
                            .w700,

                        color:
                        Color(
                          0xFF1877F2,
                        ),
                      ),
                    ),
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

                        Text(

                          conversation
                              .title,

                          style:
                          const TextStyle(

                            fontSize: 16,

                            fontWeight:
                            FontWeight
                                .w700,
                          ),
                        ),

                        const SizedBox(
                          height: 4,
                        ),

                        Text(

                          conversation
                              .latestMessage,

                          maxLines: 1,

                          overflow:
                          TextOverflow
                              .ellipsis,

                          style:
                          TextStyle(

                            color:
                            Colors
                                .grey
                                .shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(
                    width: 10,
                  ),

                  Column(

                    crossAxisAlignment:
                    CrossAxisAlignment
                        .end,

                    children: [

                      Text(

                        time,

                        style:
                        TextStyle(

                          fontSize: 12,

                          color:
                          Colors
                              .grey
                              .shade500,
                        ),
                      ),

                      const SizedBox(
                        height: 8,
                      ),

                      Icon(

                        Icons.chevron_right,

                        color:
                        Colors.grey
                            .shade400,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar:
      BottomNavigationBar(

        type:
        BottomNavigationBarType.fixed,

        selectedFontSize: 10,

        unselectedFontSize: 9,

        currentIndex: _bottomTabIndex,

        selectedItemColor:
        Colors.blueAccent,

        unselectedItemColor:
        Colors.grey,

        showSelectedLabels: true,

        showUnselectedLabels: true,

        onTap: (index) async {

          if (index == 0) {

            Navigator.pushReplacement(

              context,

              MaterialPageRoute(

                builder: (_) =>
                    DashboardScreen(

                      email:
                      widget.userEmail,

                      employeeId:
                      widget.userData['id'],
                    ),
              ),
            );

            return;
          }

          if (index == 1) {

            Navigator.push(

              context,

              MaterialPageRoute(

                builder: (_) =>
                    LeavesScreen(

                      email:
                      widget.userEmail,

                      userData:
                      widget.userData,

                      fetchHrmsContext:
                      widget.fetchHrmsContext,
                    ),
              ),
            );

            return;
          }

          if (index == 2) {

            Navigator.push(

              context,

              MaterialPageRoute(

                builder: (_) =>
                    TimeAttendanceScreen(

                      userEmail:
                      widget.userEmail,

                      userData:
                      widget.userData,

                      fetchHrmsContext:
                      widget.fetchHrmsContext,
                    ),
              ),
            );

            return;
          }

          if (index == 3) {

            Navigator.push(

              context,

              MaterialPageRoute(

                builder: (_) =>
                    PayslipScreen(

                      userEmail:
                      widget.userEmail,

                      userData:
                      widget.userData,

                      fetchHrmsContext:
                      widget.fetchHrmsContext,
                    ),
              ),
            );

            return;
          }

          if (index == 4) {

            _scaffoldKey.currentState
                ?.openEndDrawer();

            return;
          }
        },

        items: [

          BottomNavigationBarItem(

            icon: SvgPicture.asset(

              "assets/icons/dashboard.svg",

              width: 22,

              color: _bottomTabIndex == 0
                  ? Colors.blueAccent
                  : Colors.grey,
            ),

            label: 'Dashboard',
          ),

          BottomNavigationBarItem(

            icon: SvgPicture.asset(

              "assets/icons/leaves.svg",

              width: 22,

              color: _bottomTabIndex == 1
                  ? Colors.blueAccent
                  : Colors.grey,
            ),

            label: 'Leave',
          ),

          BottomNavigationBarItem(

            icon: SvgPicture.asset(

              "assets/icons/attendance.svg",

              width: 22,

              color: _bottomTabIndex == 2
                  ? Colors.blueAccent
                  : Colors.grey,
            ),

            label: 'Attendance',
          ),

          BottomNavigationBarItem(

            icon: SvgPicture.asset(

              "assets/icons/payroll.svg",

              width: 22,

              color: _bottomTabIndex == 3
                  ? Colors.blueAccent
                  : Colors.grey,
            ),

            label: 'Payslip',
          ),

          BottomNavigationBarItem(

            icon: SvgPicture.asset(

              "assets/icons/menu.svg",

              width: 22,

              color: Colors.grey,
            ),

            label: 'More',
          ),
        ],
      ),
    );
  }
}
