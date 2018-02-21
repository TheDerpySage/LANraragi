package LANraragi;

use local::lib;
use open ':std', ':encoding(UTF-8)';
use Mojo::Base 'Mojolicious';

use Mojo::IOLoop::ProcBackground;

use LANraragi::Model::Config;
use LANraragi::Model::Plugins;


# This method will run once at server start
sub startup {
  my $self = shift;

  # Load configuration from hash returned by "lrr.conf"
  my $config = $self->plugin('Config', {file => 'lrr.conf'});
  my $version = $config->{version};

  say "";
  say "";
  say "ｷﾀ━━━━━━(ﾟ∀ﾟ)━━━━━━!!!!!";
  say "LANraragi $version started.";

  my $devmode = 0;
  #Set development mode if the version number contains "DEV"
  if (index($version, "DEV") != -1) {
    $self->mode('development');
    say ("(Developer Mode)");
    $devmode = 1;
  } else {
    $self->mode('production');
    say ("(Production Mode)");
  }

  say "";

  $self->secrets($config->{secrets});
  $self->plugin('RenderFile');

  # Set Template::Toolkit as default renderer so we can use the LRR templates
  $self->plugin('TemplateToolkit');
  $self->renderer->default_handler('tt2');

  #Remove upload limit
  $self->max_request_size(0);

  #Helper so controllers can reach the app's Redis DB quickly (they still need to declare use Model::Config)
  $self->helper(LRR_CONF => sub { LANraragi::Model::Config:: });


  #Plugin listing
  my @plugins = LANraragi::Model::Plugins::plugins;
  foreach my $plugin (@plugins) {

    my %pluginfo = $plugin->plugin_info();
    my $name = $pluginfo{name};
    say "Plugin Detected: ".$name;
  }

  #Check if a Redis server is running on the provided address/port
  $self->LRR_CONF->get_redis;

  #Start Background worker if there's no lockfile present
  unless (-e "./shinobu-lock" && $devmode) {
    my $proc = $self->stash->{shinobu} = Mojo::IOLoop::ProcBackground->new;

    #Create lockfile to prevent spawn of other background processes
    open(FILE, ">shinobu-lock") || die("cannot open file: " . $!);
    close(FILE); 

    # When the process terminates, we get this event
    $proc->on(dead => sub {
        my ($proc) = @_;
        my $pid = $proc->proc->pid;
        say ("Shinobu Background Worker terminated. (PID was $pid)");

        #Delete lockfile
        unlink("./shinobu-lock");
    });

    $proc->run([$^X, "./lib/Shinobu.pm"]);

  } else { 
    say ("Lockfile present in dev mode - Background worker not respawned.");
    say ("!!! -- Delete the shinobu-lock file if you just started LANraragi.");
  }

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/')->to('index#index');
  $r->get('/index')->to('index#index');
  $r->get('/random')->to('index#random_archive');

  $r->get('/login')->to('login#index');
  $r->post('/login')->to('login#check');

  $r->get('/reader')->to('reader#index');

  $r->get('/api/thumbnail')->to('api#serve_thumbnail');
  $r->get('/api/servefile')->to('api#serve_file');

  $r->get('/stats')->to('stats#index');

  #Those routes are only accessible if user is logged in
  my $logged_in = $r->under('/')->to('login#logged_in');
  $logged_in->get('/config')->to('config#index');
  $logged_in->post('/config')->to('config#save_config');

  $logged_in->get('/config/plugins')->to('plugins#index');
  $logged_in->post('/config/plugins')->to('plugins#save_config');

  $logged_in->get('/edit')->to('edit#index');
  $logged_in->post('/edit')->to('edit#save_metadata');
  $logged_in->delete('/edit')->to('edit#delete_archive');

  $logged_in->get('/backup')->to('backup#index');
  $logged_in->post('/backup')->to('backup#restore');

  $logged_in->get('/upload')->to('upload#index');
  $logged_in->post('/upload')->to('upload#process_upload');

  $logged_in->post('/api/use_plugin')->to('api#use_plugin');
  $logged_in->post('/api/use_all_plugins')->to('api#use_enabled_plugins');
  $logged_in->get('/api/cleantemp')->to('api#clean_tempfolder');
  $logged_in->get('/api/discard_cache')->to('api#force_refresh');

  $r->get('/logout')->to('login#logout');

}

1;