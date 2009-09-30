package CatalystX::VirtualComponents;
use Moose::Role;
use namespace::clean -except => qw(meta);
use Module::Pluggable::Object;

our $VERSION = '0.00001';

sub search_components {
    my ($class, $namespace) = @_;

    my @paths   = qw( ::Controller ::C ::Model ::M ::View ::V );
    my $config  = $class->config->{ setup_components };
    my $extra   = delete $config->{ search_extra } || [];

    my @search_path = map {
        s/^(?=::)/$namespace/;
        $_;
    } @paths;
    push @search_path, @$extra;

    my $locator = Module::Pluggable::Object->new(
        search_path => [ @search_path ],
        %$config
    );

    my @comps =
        sort { length $a <=> length $b } 
        grep { !/::SUPER$/ } $locator->plugins;

    return @comps;
}

override setup_components => sub {
    my $class = shift;

    my %virtual_components;

    my @hierarchy =
        grep { $_->isa('Catalyst') && $_ ne 'Catalyst' }
        $class->meta->linearized_isa
    ;

    my @comps;
    my %comps;
    foreach my $superclass ( @hierarchy ) {
        push @comps,
            map {
                $comps{ $_ }++;
                [ $superclass, $_ ]
            } 
            $class->search_components( $superclass );
    }
    foreach my $comp (@comps) {
        my ($comp_namespace, $comp_class) = @$comp;

        next if $virtual_components{ $comp_class };

        # if this comp is not in the same namespace as myapp ($class),
        # then check if we can create a virtual component

        if ( $comp_namespace ne $class ) {
            my $base = $comp_class;
            $comp_class =~ s/^$comp_namespace/$class/;

            if ($class->components->{$comp_class}) {
                next;
            }

            eval { Class::MOP::load_class($comp_class) };
            if (my $e = $@) {
                if ($e =~ /Can't locate/) {
                    # if the module is NOT found in the current app ($class),
                    # then we build a virtual component
                    my $meta = Moose::Meta::Class->create(
                        $comp_class => ( superclasses => [ $base ] )
                    );
                    $virtual_components{ $comp_class }++;
                } else {
                    confess "Failed to load class $comp_class: $e";
                }
            }
        }

        my $module = $class->setup_component($comp_class);
        my %modules = (
            $comp_class => $module,
            map {
                $_ => $class->setup_component($_)
            } grep {
                not exists $comps{$_}
            } Devel::InnerPackage::list_packages( $comp )
        );
        for my $key ( keys %modules ) {
            $class->components->{ $key } = $modules{ $key };
        }
    }

    if ($class->debug) {
        my $column_width = Catalyst::Utils::term_width() - 6;
        my $t = Text::SimpleTable->new($column_width);
        $t->row($_) for sort keys %virtual_components;
        $class->log->debug( "Dynamically generated components:\n" . $t->draw . "\n" );
    }

};

1;

__END__

=head1 NAME

CatalystX::VirtualComponents - Setup Virtual Catalyst Components Based On A Parent Application Class

=head1 SYNOPSIS

    # in your base app...
    package MyApp;
    use Catalyst;

    # in another app...
    package MyApp::Extended;
    use Moose;
    use Catalyst qw(+CatalystX::VirtualComponents);
    
    extends 'MyApp';

=head1 DESCRIPTION

WARNING: YMMV with this module.

This module provides a way to reuse controllers, models, and views from 
another Catalyst application.

=head1 HOW IT WORKS

Suppose you have a Catalyst application with the following components:

    # Application MyApp::Base
    MyApp::Base::Controller::Root
    MyApp::Base::Model::DBIC
    MyApp::Base::View::TT

And then in MyApp::Extended, you wanted to reuse these components -- except 
you want to customize the Root controller, and you want to add another model 
(say, Model::XML::Feed).

In your new app, you can skip creating MyApp::Extended::Model::DBIC and
MyApp::Extended::View::TT -- CatalystX::VirtualComponents will take care of
these.

Just provide the customized Root controller and the new model:

    package MyApp::Extended::Controller::Root;
    use Moose;

    BEGIN { extends 'MyApp::Base::Controller::Root' }

    sub new_action :Path('new_action') {
        ....
    }

(We will skip XML::Feed, as it's just a regular model)

Then, in MyApp::Extended

    packge MyApp::Extended;
    use Moose;
    use Catalyst;

    extends 'MyApp::Base';

Note that MyApp::Extended I<inherits> from MyApp::Base. Naturally, if you
are inheriting from an application, you'd probably want to inherit all of
its controllers and such. To do this, specify CatalystX::VirtualComponents
in the Catalyst plugin list for MyApp::Extended:

    __PACKAGE__->setup( qw(
        ... # your regular Catalyst plugins
        +CatalystX::VirtualComponent
    ) );

When setup() is run, CatalystX::VirtualComponent will intercept the component
setup code and will automatically create I<virtual> subclasses for components
that exist in MyApp::Base, but I<not> in MyApp::Extended. In the above case,
MyApp::Extended::View::TT and MyApp::Extended::Model::DBIC will be created.

MyApp::Extended::Controller::Root takes precedence over the base class, so
only the local component will be loaded.  MyApp::Extended::Model::XML::Feed
only exists in the MyApp::Extended namespace, so it just works like a
normal Catalyst model.

=head1 USING IN CONJUNCTION WITH CatalystX::AppBuilder

Simply add CatalystX::VirtualComponents in the plugin list:

    package MyApp::Extended::Builder;
    use Moose;

    extends 'CatalystX::AppBuilder';

    override _build_plugins {
        my $plugins = super();
        push @$plugins, '+CatalystX::VirtualComponents';
        return $plugins;
    };

    1;

=head1 METHODS

=head2 search_components($class)

Finds the list of components for Catalyst app $class.

=head2 setup_components()

Overrides Catalyst's setup_components() method.

=head1 TODO

Documentation. Samples. Tests.

=head1 AUTHOR

Daisuke Maki C<< <daisuke@endeworks.jp> >>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut