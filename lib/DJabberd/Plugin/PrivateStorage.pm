package DJabberd::Plugin::PrivateStorage;
use strict;
use warnings;
use base 'DJabberd::Plugin';
use DJabberd::HookDocs;

our $logger = DJabberd::Log->get_logger();

use vars qw($VERSION);
$VERSION = '0.60';

DJabberd::HookDocs->allow_hook('PrivateStorageGet');
DJabberd::HookDocs->allow_hook('PrivateStorageSet');

=head2 register($self, $vhost)

Register the vhost with the module.

=cut

sub register {
    my ($self, $vhost) = @_;

    $vhost->register_hook("PrivateStorageGet", sub {
        my ($vh, $cb, $jid, $element) = @_;
        $self->get_privatestorage($cb, $jid, $element);
    });

    $vhost->register_hook("PrivateStorageSet", sub {
        my ($vh, $cb, $jid, $element, $content) = @_;
        $self->set_privatestorage($cb, $jid, $element, $content);
    });

    my $private_cb = sub {
        my ($vh, $cb, $iq) = @_;
        unless ($iq->isa("DJabberd::IQ")) {
            $cb->decline;
            return;
        }
        if(my $to = $iq->to_jid) {
            unless ($vh->handles_jid($to)) {
                $cb->decline;
                return;
            }
        }
        if ($iq->signature eq 'get-{jabber:iq:private}query') {
            $self->_get_privatestorage($vh, $iq);
            $cb->stop_chain;
            return;
        } elsif ($iq->signature eq 'set-{jabber:iq:private}query') {
            $self->_set_privatestorage($vh, $iq);
            $cb->stop_chain;
            return;
        }
        $cb->decline;
    };
    $vhost->register_hook("switch_incoming_client",$private_cb);
    $vhost->register_hook("switch_incoming_server",$private_cb);
    # should be done ?
    #$vhost->add_feature("vcard-temp");

}

sub _get_privatestorage {
    my ($self, $vhost, $iq) = @_;
    my $user  = $iq->connection->bound_jid->as_bare_string;
    my $content = $iq->first_element()->first_element();; 
    my $element = $content->element();
    $logger->info("Get private storage for user : $user, $element ");
    my $on_response = sub {
        my $cb = shift;
        my $result = shift;
        $iq->send_reply('result', qq(<query xmlns="jabber:iq:private">) 
                                  . $result 
                                  . qq(</query>) );
    };
    my $on_error = sub{
        #<iq to='brad@localhost/Gajim' type='result' id='237'>
        #   this is $iq->first_element()
        #   <query xmlns='jabber:iq:private'>
        #   <storage xmlns='storage:rosternotes'/>
        #   </query>
        #</iq>
        $iq->send_reply('result', $iq->first_element()->as_xml());
    };

    $vhost->run_hook_chain(phase => 'PrivateStorageGet',
                           args => [ $user, $element ],
                           methods => {
                               response => $on_response,
                               error => $on_error,
                           },
                           fallback => $on_error,
                          );
}

sub _set_privatestorage {
    my ($self, $vhost, $iq) = @_;

    my $user  = $iq->connection->bound_jid->as_bare_string;
    my $content = $iq->first_element()->first_element();; 
    my $element = $content->element();
    $logger->info("Set private storage for user '$user', on $element");
    my $on_error = sub {
        $iq->make_error_response('500', "wait", "internal-server-error")->deliver($vhost);
    };
    my $on_success = sub {
        $iq->make_response()->deliver($vhost);
    };

    $vhost->run_hook_chain(phase => 'PrivateStorageSet',
                           args => [ $user, $element, $content ],
                           methods => {
                               success => $on_success,
                               error => $on_error,
                           },
                           fallback => $on_error,
                          );
}

=head2 blocking

Is this a blocking or non-blocking server?

Default:

 sub blocking { 1 }

Example:

 sub blocking { 0 }

If the server is non-blocking, then define the non-blocking functions in your
subclass

=cut

sub blocking { 1 }

=head2 store_privatestorage($self, $user, $element, $content)

Store $content for $element and $user in the storage module.

Example:

 sub store_privatestorage {
     my ($self, $user, $element, $content) = @_;

     my $sql = "INSERT OR REPLACE INTO $table (user, element, content) VALUES (?, ?, ?)";
     my $res = $dbh->do($sql, {}, $user, $element, $content);

     return ($res ? 1 : 0);
 }

=cut

sub store_privatestorage {
    return undef;
}

=head2 load_privatestorage($self, $user, $element)

Return the $element for $user from the storage module.

Example:

 sub load_privatestorage {
     my ($self, $user, $element) = @_;

     my $sql = "SELECT content FROM $table WHERE user = ? AND element = ?";
     my ($content) = $dbh->selectrow_array($sql, {}, $user, $element);

     return $content;
 }

=cut

sub load_privatestorage {
    return undef;
}

1;

=head2 get_privatestorage($self, $cb, $user, $element)

Non-blocking version of load_privatestorage.  When the
response is fetched, call either $cb->response($response)
or $cb->error() if there's no response.

Default:

call load_privatestorage unless $self->blocking() returns false,
in which case die.  You need to override for that case.

Example:

 sub get_privatestorage {
     my ($self, $cb, $user, $element) = @_;

     my $handler = sub {
         my $res = shift;
         if ($res) {
             $cb->response($res);
         } else {
             $cb->error();
         }
     };

     $async->call('GetPrivateStorage', $handler, $user, $element);
 }

=cut

sub get_privatestorage {
    my ($self, $cb, $jid, $element) = @_;

    if ($self->blocking()) {
        my $response = $self->load_privatestorage($jid, $element);
        if ($response) {
            $cb->response($response);
            return;
        }
        $cb->error();
        return;
    }

    warn "you need to implement get_privatestorage for non-blocking servers\n";
    $cb->error();
    return;
}

=head2 set_privatestorage($self, $cb, $user, $element, $content)

Non-blocking version of store_privatestorage.  When the
response is fetched, call either $cb->success()
or $cb->error() if there's no response.

Default:

call store_privatestorage unless $self->blocking() returns false,
in which case die.  You need to override for that case.

Example:

 sub set_privatestorage {
     my ($self, $cb, $user, $element, $content) = @_;

     my $handler = sub {
         my $res = shift;
         if ($res) {
             $cb->success();
         } else {
             $cb->error();
         }
     };

     $async->call('SetPrivateStorage', $handler, $user, $element, $content);
 }

=cut

sub set_privatestorage {
    my ($self, $cb, $jid, $element, $content) = @_;

    if ($self->blocking()) {
        my $res = $self->store_privatestorage($jid, $element, $content);
        if ($res) {
            $cb->success();
            return;
        }
        $cb->error();
        return;
    }
    warn "you need to implement get_privatestorage for non-blocking servers\n";
    $cb->error();
    return;
}

__END__

=head1 NAME

DJabberd::Plugin::PrivateStorage - implement private storage, as described in XEP-0049

=head1 DESCRIPTION

This is the base class implementing the logic of XEP-0049, Private storage, for 
DJabberd. Derived only need to implement a storage backend.

=head1 COPYRIGHT

This module is Copyright (c) 2006 Michael Scherer
All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=head1 WARRANTY

This is free software. IT COMES WITHOUT WARRANTY OF ANY KIND.

=head1 AUTHORS

Michael Scherer <misc@zarb.org>
