package Net::Kubernetes::Role::ResourceCreator;

# ABSTRACT: Role to allow creation of resources from either objects or files.

use Moose::Role;
use MooseX::Aliases;
require YAML::XS;
require Net::Kubernetes::Resource::Service;
require Net::Kubernetes::Resource::Pod;
require Net::Kubernetes::Resource::Deployment;
require Net::Kubernetes::Resource::ReplicationController;
require Net::Kubernetes::Resource::Secret;
require Net::Kubernetes::Exception;
use File::Slurp;
use MIME::Base64 qw(encode_base64);
use syntax 'try';

with 'Net::Kubernetes::Role::ResourceFactory';

requires 'ua';
requires 'create_request';
requires 'json';
requires 'namespace';

=head2 create({OBJECT})

Creates a new L<Net::Kubernetes::Resource> (subtype determined by $BNJECT->{kind})

=head2 create_from_file(PATH_TO_FILE) (accepts either JSON or YAML files)

Create from file is really just a short cut around something like:

  my $object = YAML::LoadFile(PATH_TO_FILE);
  $kube->create($object);

=cut

sub create_from_file {
    my ($self, $file) = @_;
    if (!-f $file) {
        Throwable::Error->throw(message => "Could not read file: $file");
    }

    my $object;
    if ($file =~ /\.ya?ml$/i) {
        $object = YAML::XS::LoadFile($file);
    }
    else {
        $object = $self->json->decode(scalar(read_file($file)));
    }

    return $self->create($object);
}

sub create {
    my ($self, $object) = @_;

    # This is an ugly hack and I am not proud of it.
    # That being said, I have bigger fish to fry right now
    # This is here because kubernetes will not accept "true"
    # and "false".
    # The other problem is that YAML will read a a boolean
    # value as 1 or 0 which json does not switch back to
    # true or false. This is not JSON's fault, but I'm not
    # sure just now how I want to solve it.
    my $content = $self->json->encode($object);
    my $validBooleanProperties
        = qr/readOnly(?:RootFilesystem)?|hostNetwork|hostPID|hostIPC|stdin(?:Once)?|tty|runAsNonRoot|privileged|ready|unschedulable/;
    $content =~ s/((["'])(?:$validBooleanProperties)\2:\s)(["'])(true|false)\3/$1$4/g;

    # /EndHack

    # It looks like some objects have particular versioning and special paths.
    # Kubernetes is already training its users to provide apiVersion in the yaml
    # on a per resource level, so asking for the apiVersion per object seems
    # reasonable.
    my $resource_path = $self->url;
    if (my $version = $object->{apiVersion}) {
        if ($version =~ /\//) {
            $resource_path .= "/apis/$version";
        }
        else {
            $resource_path .= "/api/$version";
        }

        $resource_path .= "/namespaces/" . $self->namespace;
    }
    else {
        $resource_path = $self->path;
    }

    $resource_path .= '/' . lc($object->{kind}) . 's';

    my $req = $self->create_request(
        POST => $resource_path,
        undef, $content
    );
    my $res = $self->ua->request($req);
    if ($res->is_success) {
        return $self->create_resource_object($self->json->decode($res->content));
    }
    else {
        my $message;
        try {
            my $obj = $self->json->decode($res->content);
            $message = $obj->{message};
        }
        catch($e) {
            $message = $res->message;
            } Net::Kubernetes::Exception->throw(
            code    => $res->code,
            message => "Error creating resource: " . $message
            );
    }
}

return 42;
