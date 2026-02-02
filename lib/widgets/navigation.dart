import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/metadata_models.dart';
import 'library_item_context_menu.dart';

enum LibraryView { playlists, albums, artists }

class WispNavigation extends StatefulWidget {
  final LibraryView selectedView;
  final ValueChanged<LibraryView> onViewChanged;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<dynamic> libraryItems;
  final ValueChanged<dynamic> onLibraryItemSelected;
  final double expandedWidth;
  final double collapsedWidth;

  const WispNavigation({
    super.key,
    required this.selectedView,
    required this.onViewChanged,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.libraryItems,
    required this.onLibraryItemSelected,
    this.expandedWidth = 240,
    this.collapsedWidth = 88,
  });

  @override
  State<WispNavigation> createState() => _WispNavigationState();
}

class _WispNavigationState extends State<WispNavigation> {
  bool _isCollapsed = false;

  bool _isDesktop() {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  @override
  Widget build(BuildContext context) {
    return _isDesktop() ? _buildDesktopSidebar() : _buildMobileBottomNav();
  }

  Widget _buildDesktopSidebar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _isCollapsed ? widget.collapsedWidth : widget.expandedWidth,
      color: const Color(0xFF000000),
      child: Column(
        crossAxisAlignment: _isCollapsed
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() => _isCollapsed = !_isCollapsed);
                },
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisAlignment: _isCollapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Image.asset('assets/wisp.png', width: 28, height: 28),
                    if (!_isCollapsed) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'wisp',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Divider(color: Colors.grey[800], height: 1),

          // Library view selector
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _isCollapsed
                ? _buildCollapsedViewSelector()
                : _buildExpandedViewSelector(),
          ),

          // Library items list
          Expanded(
            child: ListView.builder(
              itemCount: widget.libraryItems.length,
              itemBuilder: (context, index) {
                final item = widget.libraryItems[index];
                return _buildLibraryItem(item, isCollapsed: _isCollapsed);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedViewSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR LIBRARY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
            letterSpacing: 1.5,
          ),
        ),
        SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildViewButton(Icons.playlist_play, LibraryView.playlists),
            _buildViewButton(Icons.album, LibraryView.albums),
            _buildViewButton(Icons.person, LibraryView.artists),
          ],
        ),
      ],
    );
  }

  Widget _buildCollapsedViewSelector() {
    final icon = _iconForLibraryView(widget.selectedView);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF282828),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: colorScheme.primary, size: 24),
        ),
      ],
    );
  }

  IconData _iconForLibraryView(LibraryView view) {
    switch (view) {
      case LibraryView.playlists:
        return Icons.playlist_play;
      case LibraryView.albums:
        return Icons.album;
      case LibraryView.artists:
        return Icons.person;
    }
  }

  Widget _buildViewButton(IconData icon, LibraryView view) {
    final isSelected = widget.selectedView == view;
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? Color(0xFF282828) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => widget.onViewChanged(view),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.all(8),
          child: Icon(
            icon,
            color: isSelected ? colorScheme.primary : Colors.grey[600],
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryItem(dynamic item, {required bool isCollapsed}) {
    String? imageUrl;
    String title = '';
    String? subtitle;

    // Extract data based on item type - handle different model types
    if (item is GenericPlaylist) {
      imageUrl = item.thumbnailUrl;
      title = item.title;
      subtitle = item.author.displayName;
    } else if (item is GenericAlbum) {
      imageUrl = item.thumbnailUrl;
      title = item.title;
      subtitle = item.artists.map((a) => a.name).join(', ');
    } else if (item is GenericSimpleArtist) {
      imageUrl = item.thumbnailUrl;
      title = item.name;
      subtitle = 'Artist';
    } else {
      // Fallback: try to access properties dynamically
      try {
        final dynamic obj = item;
        if (obj.thumbnailUrl != null) {
          imageUrl = obj.thumbnailUrl as String;
        }
        if (obj.title != null) {
          title = obj.title as String;
        } else if (obj.name != null) {
          title = obj.name as String;
        }
      } catch (e) {
        title = 'Unknown';
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onSecondaryTapDown: (details) {
          LibraryItemContextMenu.show(
            context: context,
            item: item,
            position: details.globalPosition,
            playlists: widget.libraryItems
                .whereType<GenericPlaylist>()
                .toList(),
            albums: widget.libraryItems.whereType<GenericAlbum>().toList(),
            artists: widget.libraryItems
                .whereType<GenericSimpleArtist>()
                .toList(),
            currentLibraryView: widget.selectedView,
            currentNavIndex: widget.selectedIndex,
          );
        },
        onTap: () {
          widget.onLibraryItemSelected(item);
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 8 : 12,
            vertical: 8,
          ),
          child: Row(
            mainAxisAlignment: isCollapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 48,
                  height: 48,
                  color: Colors.grey[900],
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) {
                            return Icon(
                              Icons.music_note,
                              color: Colors.grey[700],
                            );
                          },
                          placeholder: (context, url) =>
                              Container(color: Colors.grey[800]),
                        )
                      : Icon(Icons.music_note, color: Colors.grey[700]),
                ),
              ),
              if (!isCollapsed) ...[
                SizedBox(width: 12),
                // Text info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBottomNav() {
    final colorScheme = Theme.of(context).colorScheme;
    final destinations = [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home, color: colorScheme.primary),
        label: 'Home',
      ),
      NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search, color: colorScheme.primary),
        label: 'Search',
      ),
      NavigationDestination(
        icon: Icon(Icons.library_music_outlined),
        selectedIcon: Icon(Icons.library_music, color: colorScheme.primary),
        label: 'Library',
      ),
    ];
    final safeIndex = widget.selectedIndex.clamp(0, destinations.length - 1);
    return MediaQuery(
      data: MediaQuery.of(context).removePadding(removeTop: true),
      child: NavigationBar(
        maintainBottomViewPadding: true,
        selectedIndex: safeIndex,
        onDestinationSelected: widget.onDestinationSelected,
        backgroundColor: Color(0xFF000000),
        indicatorColor: colorScheme.primary.withOpacity(0.2),
        destinations: destinations,
      ),
    );
  }
}
