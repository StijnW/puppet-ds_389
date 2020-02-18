# ds_389::replication
#
# Sets up replication for a 389 ds instance.
#
# @summary Sets up replication for a 389 ds instance.
#
# @example A basic consumer with required params.
#   ds_389::replication { 'consumer1':
#     bind_dn      => 'cn=Replication Manager,cn=config',
#     bind_dn_pass => 'supersecret',
#     root_dn      => 'cn=Directory Manager',
#     root_dn_pass => 'supersecure',
#     role         => 'consumer',
#     suffix       => 'dc=example,dc=com',
#   }
#
# @example A basic hub with 2 consumers.
#   ds_389::replication { 'hub1':
#     bind_dn      => 'cn=Replication Manager,cn=config',
#     bind_dn_pass => 'supersecret',
#     root_dn      => 'cn=Directory Manager',
#     root_dn_pass => 'supersecure',
#     role         => 'hub',
#     suffix       => 'dc=example,dc=com',
#     consumers    => [
#       'consumer1',
#       'consumer2',
#     ],
#   }
#
# @example A basic supplier in multi-master mode with 2 other suppliers and initializing replication.
#   ds_389::replication { 'supplier1':
#     bind_dn        => 'cn=Replication Manager,cn=config',
#     bind_dn_pass   => 'supersecret',
#     root_dn        => 'cn=Directory Manager',
#     root_dn_pass   => 'supersecure',
#     role           => 'supplier',
#     suffix         => 'dc=example,dc=com',
#     init_suppliers => true,
#     suppliers      => [
#       'supplier1',
#       'supplier2',
#     ],
#   }
#
# @param bind_dn The bind dn of the replication user. Required.
# @param bind_dn_pass The bind dn password of the replication user. Required.
# @param root_dn The root dn for configuring replication. Required.
# @param root_dn_pass The root dn password for configuring replication. Required.
# @param role Replication role. Either 'supplier', 'hub', or 'consumer'. Required.
# @param suffix The LDAP suffix to use. Required.
# @param server_host The host to use when calling ldapmodify. Default: $::fqdn
# @param server_port The port to use when calling ldapmodify. Default: 389
# @param protocol The protocol to use when calling ldapmodify. Default: 'ldap'
# @param starttls Whether to use StartTLS when calling ldapmodify. Default: false
# @param replica_port The port to use for replication. Default: 389
# @param replica_transport The transport type to use for replication. Default: 'LDAP'
# @param user The owner of the created ldif file. Default: $::ds_389::user
# @param group The group of the created ldif file. Default: $::ds_389::group
# @param id The replica id. Optional unless declaring a supplier.
# @param purge_delay Time in seconds state information stored in replica entries is retained. Default: 604800
# @param suppliers An array of supplier names to ensure. Optional.
# @param hubs An array of hub names to ensure. Optional.
# @param consumers An array of consumer names to ensure. Optional.
# @param excluded_attributes An array of attributes to exclude from replication. Optional.
# @param init_suppliers Whether to initialize replication for suppliers. Default: false
# @param init_hubs Whether to initialize replication for hubs. Default: false
# @param init_consumers Whether to initialize replication for consumers. Default: false
#
define ds_389::replication(
  Variant[String,Sensitive[String]] $replication_pass,
  String                            $root_dn,
  Variant[String,Sensitive[String]] $root_dn_pass,
  Enum['supplier','hub','consumer'] $role,
  String                            $suffix,
  String                            $replication_user    = 'Replication Manager',
  Optional[String]                  $bind_dn             = undef,
  String                            $server_host         = $::fqdn,
  Integer                           $server_port         = 389,
  Enum['ldap','ldaps']              $protocol            = 'ldap',
  Boolean                           $starttls            = false,
  Integer                           $replica_port        = 389,
  Enum['LDAP','SSL','TLS']          $replica_transport   = 'LDAP',
  String                            $user                = $::ds_389::user,
  String                            $group               = $::ds_389::group,
  Optional[Integer]                 $id                  = undef,
  Integer                           $purge_delay         = 604800,
  Optional[Array]                   $suppliers           = undef,
  Optional[Array]                   $hubs                = undef,
  Optional[Array]                   $consumers           = undef,
  Optional[Array]                   $excluded_attributes = undef,
  Boolean                           $init_suppliers      = false,
  Boolean                           $init_hubs           = false,
  Boolean                           $init_consumers      = false,
) {

  if $bind_dn {
    $_bind_dn = $bind_dn
  }
  else {
    $_bind_dn = "cn=${replication_user},cn=config"
  }

  if $starttls {
    $_opts = 'ZxH'
  }
  else {
    $_opts = 'xH'
  }

  case $role {
    'consumer': {
      $type = 2
      $flags = 0
      $_id = 65535
    }
    'hub': {
      $type = 2
      $flags = 1
      $_id = 65535

      if $consumers {
        $consumers.each |$replica| {
          if $replica != $name and $replica != $::fqdn {
            file { "/etc/dirsrv/slapd-${name}/consumer_${replica}.ldif":
              ensure  => file,
              mode    => '0440',
              owner   => $user,
              group   => $group,
              content => template('ds_389/replication_agreement.erb'),
            }
            exec { "Create replication agreement for consumer ${replica}: ${name}":
              command => "ldapmodify -${_opts} ${protocol}://${server_host}:${server_port} -D \"${root_dn}\" -w ${root_dn_pass} -f /etc/dirsrv/slapd-${name}/consumer_${replica}.ldif && touch /etc/dirsrv/slapd-${name}/consumer_${replica}.done", # lint:ignore:140chars
              path    => '/usr/bin:/bin',
              creates => "/etc/dirsrv/slapd-${name}/consumer_${replica}.done",
              require => [
                File["/etc/dirsrv/slapd-${name}/consumer_${replica}.ldif"],
                Exec["Set up replication: ${name}"],
              ],
            }

            if $init_consumers {
              file { "/etc/dirsrv/slapd-${name}/consumer_${replica}_init.ldif":
                ensure  => file,
                mode    => '0440',
                owner   => $user,
                group   => $group,
                content => template('ds_389/replication_init.erb'),
              }
              exec { "Initialize consumer ${replica}: ${name}":
                command => "ldapmodify -${_opts} ${protocol}://${server_host}:${server_port} -D \"${root_dn}\" -w ${root_dn_pass} -f /etc/dirsrv/slapd-${name}/consumer_${replica}_init.ldif && touch /etc/dirsrv/slapd-${name}/consumer_${replica}_init.done", # lint:ignore:140chars
                path    => '/usr/bin:/bin',
                creates => "/etc/dirsrv/slapd-${name}/consumer_${replica}_init.done",
                require => [
                  File["/etc/dirsrv/slapd-${name}/consumer_${replica}_init.ldif"],
                  Exec["Create replication agreement for consumer ${replica}: ${name}"],
                ],
              }
            }
          }
        }
      }
    }
    # otherwise supplier (master or multi-master)
    default: {
      unless $id {
        fail('$id is required when declaring a replication supplier')
      }
      $_id = $id

      $type = 3
      $flags = 1

      if $suppliers {
        $suppliers.each |$replica| {
          if $replica != $name and $replica != $::fqdn {
            file { "/etc/dirsrv/slapd-${name}/supplier_${replica}.ldif":
              ensure  => file,
              mode    => '0440',
              owner   => $user,
              group   => $group,
              content => template('ds_389/replication_agreement.erb'),
            }
            exec { "Create replication agreement for supplier ${replica}: ${name}":
              command => "ldapmodify -${_opts} ${protocol}://${server_host}:${server_port} -D \"${root_dn}\" -w ${root_dn_pass} -f /etc/dirsrv/slapd-${name}/supplier_${replica}.ldif && touch /etc/dirsrv/slapd-${name}/supplier_${replica}.done", # lint:ignore:140chars
              path    => '/usr/bin:/bin',
              creates => "/etc/dirsrv/slapd-${name}/supplier_${replica}.done",
              require => [
                File["/etc/dirsrv/slapd-${name}/supplier_${replica}.ldif"],
                Exec["Set up replication: ${name}"],
              ],
            }

            if $init_suppliers {
              file { "/etc/dirsrv/slapd-${name}/supplier_${replica}_init.ldif":
                ensure  => file,
                mode    => '0440',
                owner   => $user,
                group   => $group,
                content => template('ds_389/replication_init.erb'),
              }
              exec { "Initialize supplier ${replica}: ${name}":
                command => "ldapmodify -${_opts} ${protocol}://${server_host}:${server_port} -D \"${root_dn}\" -w ${root_dn_pass} -f /etc/dirsrv/slapd-${name}/supplier_${replica}_init.ldif && touch /etc/dirsrv/slapd-${name}/supplier_${replica}_init.done", # lint:ignore:140chars
                path    => '/usr/bin:/bin',
                creates => "/etc/dirsrv/slapd-${name}/supplier_${replica}_init.done",
                require => [
                  File["/etc/dirsrv/slapd-${name}/supplier_${replica}_init.ldif"],
                  Exec["Create replication agreement for supplier ${replica}: ${name}"],
                ],
              }
            }
          }
        }
      }
      if $hubs {
        $hubs.each |$replica| {
          if $replica != $name and $replica != $::fqdn {
            file { "/etc/dirsrv/slapd-${name}/hub_${replica}.ldif":
              ensure  => file,
              mode    => '0440',
              owner   => $user,
              group   => $group,
              content => template('ds_389/replication_agreement.erb'),
            }
            exec { "Create replication agreement for hub ${replica}: ${name}":
              command => "ldapmodify -${_opts} ${protocol}://${server_host}:${server_port} -D \"${root_dn}\" -w ${root_dn_pass} -f /etc/dirsrv/slapd-${name}/hub_${replica}.ldif && touch /etc/dirsrv/slapd-${name}/hub_${replica}.done", # lint:ignore:140chars
              path    => '/usr/bin:/bin',
              creates => "/etc/dirsrv/slapd-${name}/hub_${replica}.done",
              require => [
                File["/etc/dirsrv/slapd-${name}/hub_${replica}.ldif"],
                Exec["Set up replication: ${name}"],
              ],
            }

            if $init_hubs {
              file { "/etc/dirsrv/slapd-${name}/hub_${replica}_init.ldif":
                ensure  => file,
                mode    => '0440',
                owner   => $user,
                group   => $group,
                content => template('ds_389/replication_init.erb'),
                require => Anchor["${name}_replication_suppliers"],
              }
              exec { "Initialize hub ${replica}: ${name}":
                command => "ldapmodify -${_opts} ${protocol}://${server_host}:${server_port} -D \"${root_dn}\" -w ${root_dn_pass} -f /etc/dirsrv/slapd-${name}/hub_${replica}_init.ldif && touch /etc/dirsrv/slapd-${name}/hub_${replica}_init.done", # lint:ignore:140chars
                path    => '/usr/bin:/bin',
                creates => "/etc/dirsrv/slapd-${name}/hub_${replica}_init.done",
                require => [
                  File["/etc/dirsrv/slapd-${name}/hub_${replica}_init.ldif"],
                  Exec["Create replication agreement for hub ${replica}: ${name}"],
                ],
              }
            }
          }
        }
      }
      if $consumers {
        $consumers.each |$replica| {
          if $replica != $name and $replica != $::fqdn {
            file { "/etc/dirsrv/slapd-${name}/consumer_${replica}.ldif":
              ensure  => file,
              mode    => '0440',
              owner   => $user,
              group   => $group,
              content => template('ds_389/replication_agreement.erb'),
              require => Anchor["${name}_replication_hubs"],
            }
            exec { "Create replication agreement for consumer ${replica}: ${name}":
              command => "ldapmodify -${_opts} ${protocol}://${server_host}:${server_port} -D \"${root_dn}\" -w ${root_dn_pass} -f /etc/dirsrv/slapd-${name}/consumer_${replica}.ldif && touch /etc/dirsrv/slapd-${name}/consumer_${replica}.done", # lint:ignore:140chars
              path    => '/usr/bin:/bin',
              creates => "/etc/dirsrv/slapd-${name}/consumer_${replica}.done",
              require => [
                File["/etc/dirsrv/slapd-${name}/consumer_${replica}.ldif"],
                Exec["Set up replication: ${name}"],
              ],
            }

            if $init_consumers {
              file { "/etc/dirsrv/slapd-${name}/consumer_${replica}_init.ldif":
                ensure  => file,
                mode    => '0440',
                owner   => $user,
                group   => $group,
                content => template('ds_389/replication_init.erb'),
                require => Anchor["${name}_replication_consumers"],
              }
              exec { "Initialize consumer ${replica}: ${name}":
                command => "ldapmodify -${_opts} ${protocol}://${server_host}:${server_port} -D \"${root_dn}\" -w ${root_dn_pass} -f /etc/dirsrv/slapd-${name}/consumer_${replica}_init.ldif && touch /etc/dirsrv/slapd-${name}/consumer_${replica}_init.done", # lint:ignore:140chars
                path    => '/usr/bin:/bin',
                creates => "/etc/dirsrv/slapd-${name}/consumer_${replica}_init.done",
                require => [
                  File["/etc/dirsrv/slapd-${name}/consumer_${replica}_init.ldif"],
                  Exec["Create replication agreement for consumer ${replica}: ${name}"],
                ],
              }
            }
          }
        }
      }
    }
  }

  if $excluded_attributes {
    $attribute_list = join($excluded_attributes, ' ')
  }
  file { "/etc/dirsrv/slapd-${name}/replication.ldif":
    ensure  => file,
    mode    => '0440',
    owner   => $user,
    group   => $group,
    content => template('ds_389/replication.erb'),
  }
  exec { "Set up replication: ${name}":
    command => "ldapmodify -${_opts} ${protocol}://${server_host}:${server_port} -D \"${root_dn}\" -w ${root_dn_pass} -f /etc/dirsrv/slapd-${name}/replication.ldif && touch /etc/dirsrv/slapd-${name}/replication.done", # lint:ignore:140chars
    path    => '/usr/bin:/bin',
    creates => "/etc/dirsrv/slapd-${name}/replication.done",
    require => [
      File["/etc/dirsrv/slapd-${name}/replication.ldif"],
      Ds_389::Ssl[$name],
    ],
  }
  anchor { "${name}_replication_suppliers":
    require => Exec["Set up replication: ${name}"],
  }
  anchor { "${name}_replication_hubs":
    require => Anchor["${name}_replication_suppliers"],
  }
  anchor { "${name}_replication_consumers":
    require => Anchor["${name}_replication_hubs"],
  }
}
