package Net::Kubernetes;

use Moose;
use Data::Dumper;
require Net::Kubernetes::Namespace;
require LWP::UserAgent;
require HTTP::Request;
require JSON;
require URI;;
require Throwable::Error;
use MIME::Base64;
require Net::Kubernetes::Exception;

# ABSTRACT: Perl interface to kubernetes

=head1 NAME

Net::Kubernetes

=head1 SYNOPSIS

  my $kube = Net::Kubernets->new(url=>'http://127.0.0.1:8080', username=>'dave', password=>'davespassword');
  my $pod_list = $kube->list_pods();
  
  my $nginx_pod = $kube->create_from_file('kubernetes/examples/pod.yaml');
  
  my $ns = $kube->get_namespace('default');
  
  my $services = $ns->list_services;

=cut

with 'Net::Kubernetes::Role::APIAccess';
with 'Net::Kubernetes::Role::ResourceLister';
with 'Net::Kubernetes::Role::ResourceCreator';

=head1 Methods

By convention, methods will throw exceptions if kubernetes api server returns a non-successful status code.

=head2 List resources

These methods retrieve lists (optionally limited by field or label selector) of the various resources types
kubernetes makes available via the API servers rest interface. These methods may also be called on a
"Namespace" object, which will implicitly limit the result set by namespace.

All of these methods will return an array (or and array ref denpending on context) of the approriate
resource type (Net::Kubernetes::Resource::Pod for example).

=over 1

=item $kube->list_pods([label=>{label=>value}], [fields=>{field=>value}])

=item $kube->list_rc([label=>{label=>value}], [fields=>{field=>value}])

=item $kube->list_replication_controllers([label=>{label=>value}], [fields=>{field=>value}]) (alias to list_rc)

=item $kube->list_secrets([label=>{label=>value}], [fields=>{field=>value}])

=item $kube->list_services([label=>{label=>value}], [fields=>{field=>value}])

=back

=head2 Create Methods

These methods may be called either globally or on a namespace object. The return value is is an object of the
approriate type (determined by the "Kind" field)

=over 1

=item my $resource = $kube->create({OBJECT})

=item my $resource = $kube->create_from_file(PATH_TO_FILE) (accepts either JSON or YAML files)

Create from file is really just a short cut around something like:

  my $object = YAML::LoadFile(PATH_TO_FILE);
  $kube->create($object);

=back

=head2 Global scoped methods

These methods are only available at the top level (i.e. not available via a namespace object)

=over 1

=item $kube->get_namespace("myNamespace");

This method returns a "Namespace" object on which many methods can be called implicitly
limited to the specified namespace.

=cut

sub get_namespace {
	my($self, $namespace) = @_;
	if (! defined $namespace || ! length $namespace) {
		Throwable::Error->throw(message=>'$namespace cannot be null');
	}
	
	my $res = $self->ua->request($self->create_request(GET => $self->url.'/namespaces/'.$namespace));
	if ($res->is_success) {
		my $ns = $self->json->decode($res->content);
		my(%create_args) = (url => $self->url.'/namespaces/'.$namespace	, namespace=> $namespace, _namespace_data=>$ns);
		$create_args{username} = $self->username if(defined $self->username);
		$create_args{password} = $self->password if(defined $self->password);
		return Net::Kubernetes::Namespace->new(%create_args);
	}else{
		Net::Kubernetes::Exception->throw(code=>$res->code, message=>"Error getting namespace $namespace:\n".$res->message);
	}
}

return 42;

=back

=head1 AUTHOR

  Dave Mueller <dave@perljedi.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Dave Mueller.

This is free software; you can redistribute it and/or modify it under the
same terms as the Perl 5 programming language system itself.
