%global debug_package %{nil}
%global sname   pg_repack
%global pgmajorversion 11
%global pginstdir /usr/pgsql-11

Summary:        Reorganize tables in PostgreSQL databases without any locks
Name:           %{sname}%{pgmajorversion}
Version:        %{version}
Release:        2%{?dist}
Epoch:          1
License:        BSD
Group:          Applications/Databases
Source0:        %{sname}-%{version}.tar.gz
Patch0:         pg_repack-pg%{pgmajorversion}-makefile-pgxs.patch
URL:            https://pgxn.org/dist/pg_repack/
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-%(%{__id_u} -n)

BuildRequires:  percona-platform-postgresql%{pgmajorversion}-devel, percona-platform-postgresql%{pgmajorversion}
Requires:       percona-platform-postgresql%{pgmajorversion}


%description
pg_repack can re-organize tables on a postgres database without any locks so that
you can retrieve or update rows in tables being reorganized.
The module is developed to be a better alternative of CLUSTER and VACUUM FULL.

%prep
%setup -q -n %{sname}-%{version}
%patch0 -p0

%build
USE_PGXS=1 make %{?_smp_mflags}


%install
%{__rm} -rf %{buildroot}
USE_PGXS=1 make DESTDIR=%{buildroot} install

%files
%defattr(644,root,root)
%doc COPYRIGHT doc/pg_repack.rst
%attr (755,root,root) %{pginstdir}/bin/pg_repack
%attr (755,root,root) %{pginstdir}/lib/pg_repack.so
%{pginstdir}/share/extension/%{sname}--%{version}.sql
%{pginstdir}/share/extension/%{sname}.control
%{pginstdir}/lib/bitcode/%{sname}*.bc
%{pginstdir}/lib/bitcode/%{sname}/*.bc
%{pginstdir}/lib/bitcode/%{sname}/pgut/*.bc

%clean
%{__rm} -rf %{buildroot}

%changelog
* Tue Aug 30 2019 Evgeniy Patlan <evgeniy.patlan@percona.com> - 1.4.4-2
- Initial build
