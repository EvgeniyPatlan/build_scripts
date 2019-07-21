%define pginstdir /usr/pgsql-11/

Name:           pgaudit
Version:        1.3.0
Release:        2%{?dist}
Summary:        PostgreSQL Audit Extension

License:        PostgreSQL
URL:            http://pgaudit.org
Epoch:          1
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  percona-platform-postgresql11-server >= 11, percona-platform-postgresql11-server < 12
BuildRequires:  percona-platform-postgresql11-devel >= 11, percona-platform-postgresql11-devel < 12
BuildRequires:  openssl-devel percona-platform-postgresql-common

Requires:       percona-platform-postgresql11 percona-platform-postgresql11-libs percona-platform-postgresql11-server

%description
The PostgreSQL Audit extension (pgaudit) provides detailed session
and/or object audit logging via the standard PostgreSQL logging
facility.

The goal of the PostgreSQL Audit extension (pgaudit) is to provide
PostgreSQL users with capability to produce audit logs often required to
comply with government, financial, or ISO certifications.

An audit is an official inspection of an individual's or organization's
accounts, typically by an independent body. The information gathered by
the PostgreSQL Audit extension (pgaudit) is properly called an audit
trail or audit log. The term audit log is used in this documentation.


%prep
%setup -q -n %{name}-%{version}


%build
sed -i 's:PG_CONFIG = pg_config:PG_CONFIG = /usr/pgsql-11/bin/pg_config:' Makefile
%{__make} USE_PGXS=1 %{?_smp_mflags}


%install
%{__make}  USE_PGXS=1 %{?_smp_mflags} DESTDIR=%{buildroot} install
# Install README and howto file under PostgreSQL installation directory:
%{__install} -d %{buildroot}%{pginstdir}/doc/extension
%{__install} -m 644 README.md %{buildroot}%{pginstdir}/doc/extension/README-%{name}.md
%{__rm} -f %{buildroot}%{pginstdir}/doc/extension/README.md



%files
%defattr(-,root,root,-)
%doc %{pginstdir}/doc/extension/README-%{name}.md
%{pginstdir}/lib/%{name}.so
%{pginstdir}/share/extension/pgaudit--1.3*.sql
%{pginstdir}/lib/bitcode/%{name}*.bc
%{pginstdir}/lib/bitcode/%{name}/%{name}*.bc
%{pginstdir}/share/extension/%{name}.control


%changelog
* Sun Jul 21 2019 Evgeniy Patlan <evgeniy.patlan@percona.com> - 1.3.0-2
- Initial build