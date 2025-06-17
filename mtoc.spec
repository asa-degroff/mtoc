Name:           mtoc
Version:        1.1.1
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

