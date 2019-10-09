%global sname percona-postgresql-mongo_fdw
%global relver 5_2_0
%global pginstdir /usr/pgsql-11/
%global pgmajorversion 11

Summary:        PostgreSQL foreign data wrapper for MongoDB
Name:           %{sname}%{pgmajorversion}
Version:        5.2.6
Release:        1%{?dist}
License:        BSD
Group:          Applications/Databases
Source0:        %{sname}-%{version}.tar.gz
Source1:        mongo_fdw-config.h
URL:            https://github.com/Percona-Lab/mongodb_fdw
BuildRequires:  postgresql%{pgmajorversion}-devel
BuildRequires:  mongo-c-driver-devel snappy snappy-devel wget
Requires:       postgresql%{pgmajorversion}-server
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Provides:       mongo_fdw postgresql-mongo-fdw


%description
This PostgreSQL extension implements a Foreign Data Wrapper (FDW) for
MongoDB.


%prep
%setup -q -n %{sname}-%{version}
sed -i 's:PG_CONFIG = pg_config:PG_CONFIG = /usr/pgsql-11/bin/pg_config:' Makefile
sed -i 's:PG_CONFIG = pg_config:PG_CONFIG = /usr/pgsql-11/bin/pg_config:' Makefile.meta
%{__cp} %{SOURCE1} ./config.h


%build
CFLAGS="$RPM_OPT_FLAGS -fPIC"; export CFLAGS
sh autogen.sh --with-master
%{__make} -f Makefile USE_PGXS=1 %{?_smp_mflags}


%install
%{__rm} -rf %{buildroot}
%{__make} -f Makefile.meta USE_PGXS=1 %{?_smp_mflags} install DESTDIR=%{buildroot}
# Install README file under PostgreSQL installation directory:
%{__install} -d %{buildroot}%{pginstdir}/share/extension
%{__install} -m 755 README.md %{buildroot}%{pginstdir}/share/extension/README-mongo_fdw.md
%{__rm} -f %{buildroot}%{_docdir}/pgsql/extension/README.md


%clean
%{__rm} -rf %{buildroot}


%post -p /sbin/ldconfig


%postun -p /sbin/ldconfig


%files
%defattr(644,root,root,755)
%doc LICENSE
%{pginstdir}/lib/mongo_fdw.so
%{pginstdir}/share/extension/README-mongo_fdw.md
%{pginstdir}/share/extension/mongo_fdw*.sql
%{pginstdir}/share/extension/mongo_fdw.control
%{pginstdir}/lib/bitcode/mongo_fdw*.bc
%{pginstdir}/lib/bitcode/mongo_fdw/*.bc
%{pginstdir}/lib/bitcode/mongo_fdw/json-c/*.bc

%changelog
* Wed Oct  9 2019 - Evgeniy Patlan <evgeniy.patlan@percona.com> 5.2.0-1
- Initial build
