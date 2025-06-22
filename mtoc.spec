Name:           mtoc
Version:        1.1.4
Release:        1%{?dist}
Summary:        Music player and library browsing application

License:        GPL-3.0
URL:            https://github.com/asa-degroff/mtoc
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cmake >= 3.16
BuildRequires:  gcc-c++
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  qt6-qtmultimedia-devel
BuildRequires:  qt6-qttools-devel
BuildRequires:  taglib-devel
BuildRequires:  gstreamer1-devel
BuildRequires:  pkgconfig
BuildRequires:  desktop-file-utils

Requires:       qt6-qtbase
Requires:       qt6-qtdeclarative
Requires:       qt6-qtmultimedia
Requires:       qt6-qtquickcontrols2
Requires:       taglib
Requires:       gstreamer1
Requires:       gstreamer1-plugins-base
Requires:       gstreamer1-plugins-good

%description
mtoc is a music player and library browser for Linux that emphasizes smooth, continuous browsing experiences with album artwork at the forefront.

%prep
%autosetup -n %{name}-%{version}

%build
%cmake
%cmake_build

%install
%cmake_install

# Validate desktop file
desktop-file-validate %{buildroot}%{_datadir}/applications/%{name}.desktop

%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_bindir}/mtoc_app
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.*
%{_datadir}/pixmaps/%{name}.png

%changelog
* Sat Jun 21 2025 Asa DeGroff <asa@3fz.org> 1.1.4-1
- feat: add caching for artist albums to improve lookup performance in
  LibraryPane (asa@3fz.org)
- perf: optimize image handling and caching in BlurredBackground and
  LibraryPane components (asa@3fz.org)
- feat: improve keyboard navigation handling for album and track lists
  (asa@3fz.org)
- feat: enhance search functionality with enter key handling and improved
  keyboard navigation (asa@3fz.org)
- fix: search results now move to the top of the view (asa@3fz.org)
- feat: add layer effects to maintain rounded corners during scrolling in
  artist and track lists (asa@3fz.org)
- Automatic commit of package [mtoc] release [1.1.3-1]. (asa@3fz.org)
- feat: implement carousel position persistence between restarts in
  HorizontalAlbumBrowser (asa@3fz.org)
- cleanup (asa@3fz.org)
- Automatic commit of package [mtoc] release [1.1.2-1]. (asa@3fz.org)

* Thu Jun 19 2025 Asa DeGroff <asa@3fz.org> 1.1.3-1
- perf: improved performance in LibraryManager by replacing linear search with
  constant time lookup for artists and albums (asa@3fz.org)
- perf: implement parallelized metadata extraction and batch insertion in
  LibraryManager (asa@3fz.org)
- feat: add pagination and caching for album retrieval in LibraryManager
  (asa@3fz.org)
- fix: ensure proper memory management by setting LibraryManager as parent for
  TrackModel and AlbumModel instances (asa@3fz.org)
- Pruned librarymanager (asa@3fz.org)
- feat: implement carousel position persistence between restarts in
  HorizontalAlbumBrowser (asa@3fz.org)
- cleanup (asa@3fz.org)
- fix: enhance icon handling for Flatpak integration (asa@3fz.org)
- fix: add  proper display path mapping in UI for music folders when using
  flatpak (asa@3fz.org)
- Flatpak distribution preparation (asa@3fz.org)

* Wed Jun 18 2025 Asa DeGroff <asa@3fz.org> 1.1.2-1
- fix: adjust progress slider positioning and dimensions for better alignment
  (asa@3fz.org)

* Wed Jun 18 2025 Asa DeGroff <asa@3fz.org>
- fix: adjust progress slider positioning and dimensions for better alignment
  (asa@3fz.org)

* Tue Jun 17 2025 Asa DeGroff <asa@3fz.org> 1.1.1-1
- bump version and update readme (asa@3fz.org)

* Mon Jun 16 2025 Asa DeGroff <asa@3fz.org> 1.1-1
- This update includes new touchpad-specific navigation for the carousel that directly manipulates content with inertial flicking and snapping. 
* Sun Jun 15 2025 Asa DeGroff <asa@3fz.org> 1.0.9-1
- style: centered position of media control button icons (asa@3fz.org)
- now playing layout tweaks (asa@3fz.org)
- layout tweaks for higher density in the library pane (asa@3fz.org)
- refactor: simplify library header with minimal design and reduced dimensions
  (asa@3fz.org)
- cangelog (asa@3fz.org)
- update gitignore (asa@3fz.org)

* Sat Jun 14 2025 Asa DeGroff <asa@3fz.org> 1.0.8-1
- 

* Sat Jun 14 2025 Asa DeGroff <asa@3fz.org> 1.0.7-1
- Initial package

