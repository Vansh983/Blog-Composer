<?php

/**
 * @file
 * Enables modules and site configuration for a blogcomposer site installation.
 */

 //This code is inpired from open social distribution.

use Drupal\user\Entity\User;
use Drupal\Core\Form\FormStateInterface;
use Drupal\features\FeaturesManagerInterface;
use Drupal\features\ConfigurationItem;
use Drupal\search_api\Entity\Index;

/**
 * Implements hook_install_tasks().
 */
function blogcomposer_install_tasks(&$install_state) {
  $tasks = [
    'blogcomposer_install_profile_modules' => [
      'display_name' => t('Install Open blogcomposer modules'),
      'type' => 'batch',
    ],
    'blogcomposer_final_site_setup' => [
      'display_name' => t('Apply configuration'),
      'type' => 'batch',
      'display' => TRUE,
    ],
    'blogcomposer_theme_setup' => [
      'display_name' => t('Apply theme'),
      'display' => TRUE,
    ],
  ];
  return $tasks;
}

/**
 * Implements hook_install_tasks_alter().
 *
 * Unfortunately we have to alter the verify requirements.
 * This is because of https://www.drupal.org/node/1253774. The dependencies of
 * dependencies are not tested. So adding requirements to our install profile
 * hook_requirements will not work :(. Also take a look at install.inc function
 * drupal_check_profile() it just checks for all the dependencies of our
 * install profile from the info file. And no actually hook_requirements in
 * there.
 */
function blogcomposer_install_tasks_alter(&$tasks, $install_state) {
  // Override the core install_verify_requirements task function.
  $tasks['install_verify_requirements']['function'] = 'blogcomposer_verify_custom_requirements';
  // Override the core finished task function.
  $tasks['install_finished']['function'] = 'blogcomposer_install_finished';
}

/**
 * Callback for install_verify_requirements, so that we meet custom requirement.
 *
 * @param array $install_state
 *   The current install state.
 *
 * @return array
 *   All the requirements we need to meet.
 */
function blogcomposer_verify_custom_requirements(array &$install_state) {
  // Copy pasted from install_verify_requirements().
  // @todo when composer hits remove this.
  // Check the installation requirements for Drupal and this profile.
  $requirements = install_check_requirements($install_state);

  // Verify existence of all required modules.
  $requirements += drupal_verify_profile($install_state);

  // Added a custom check for users to see if the Address libraries are
  // downloaded.
  if (!class_exists('\CommerceGuys\Addressing\Address')) {
    $requirements['addressing_library'] = [
      'title' => t('Address module requirements)'),
      'value' => t('Not installed'),
      'description' => t('The Address module requires the commerceguys/addressing library. <a href=":link" target="_blank">For more information check our readme</a>', [':link' => 'https://github.com/goalgorilla/drupal_blogcomposer/blob/master/readme.md#install-from-project-page-on-drupalorg']),
      'severity' => REQUIREMENT_ERROR,
    ];
  }

  if (!class_exists('\Facebook\Facebook')) {
    $requirements['social_auth_facebook'] = [
      'title' => t('social auth Facebook module requirements'),
      'value' => t('Not installed'),
      'description' => t('social auth Facebook requires Facebook PHP Library. Make sure the library is installed via Composer.'),
      'severity' => REQUIREMENT_ERROR,
    ];
  }

  if (!class_exists('\Google_Client')) {
    $requirements['social_auth_google'] = [
      'title' => t('social auth Google module requirements'),
      'value' => t('Not installed'),
      'description' => t('social auth Google requires Google_Client PHP Library. Make sure the library is installed via Composer.'),
      'severity' => REQUIREMENT_ERROR,
    ];
  }

  if (!class_exists('\Happyr\LinkedIn\LinkedIn')) {
    $requirements['social_auth_linkedin'] = [
      'title' => t('social auth LinkedIn module requirements'),
      'value' => t('Not installed'),
      'description' => t('social auth LinkedIn requires LinkedIn PHP Library. Make sure the library is installed via Composer.'),
      'severity' => REQUIREMENT_ERROR,
    ];
  }

  if (!class_exists('\Abraham\TwitterOAuth\TwitterOAuth')) {
    $requirements['social_auth_twitter'] = [
      'title' => t('social auth Twitter module requirements'),
      'value' => t('Not installed'),
      'description' => t('social auth Twitter requires TwitterOAuth PHP Library. Make sure the library is installed via Composer.'),
      'severity' => REQUIREMENT_ERROR,
    ];
  }

  return install_display_requirements($install_state, $requirements);
}

/**
 * Implements hook_form_FORM_ID_alter() for install_configure_form().
 *
 * Allows the profile to alter the site configuration form.
 */
function blogcomposer_form_install_configure_form_alter(&$form, FormStateInterface $form_state) {

  // Add 'blogcomposer' fieldset and options.
  $form['blogcomposer'] = [
    '#type' => 'fieldgroup',
    '#title' => t('Open blogcomposer optional configuration'),
    '#description' => t('All the required modules and configuration will be automatically installed and imported. You can optionally select additional features or generated demo content.'),
    '#weight' => 50,
  ];

  $blogcomposer_optional_modules = [
    'blogcomposer_book' => t('Book functionality'),
    'blogcomposer_sharing' => t('Share content on blogcomposer media'),
    'blogcomposer_event_type' => t('Categorize events in event types'),
    'blogcomposer_sso' => t('Registration with blogcomposer networks'),
    'blogcomposer_file_private' => t('Use the private file system for uploaded files (highly recommended)'),
    'inline_form_errors' => t('Inline Form Errors'),
    'page_cache' => t('Cache page for anonymous users (highly recommended)'),
    'dynamic_page_cache' => t('Cache pages for any user (highly recommended)'),
  ];

  // Checkboxes to enable Optional modules.
  $form['blogcomposer']['optional_modules'] = [
    '#type' => 'checkboxes',
    '#title' => t('Enable additional features'),
    '#options' => $blogcomposer_optional_modules,
    '#default_value' => [
      'blogcomposer_file_private',
      'inline_form_errors',
      'page_cache',
      'dynamic_page_cache',
    ],
  ];

  // Checkboxes to generate demo content.
  $form['blogcomposer']['demo_content'] = [
    '#type' => 'checkbox',
    '#title' => t('Generate demo content and users'),
    '#description' => t('Will generate files, users, groups, events, topics, comments and posts.'),
  ];

  // Submit handler to enable features.
  $form['#submit'][] = 'blogcomposer_features_submit';
}

/**
 * Submit handler.
 */
function blogcomposer_features_submit($form_id, &$form_state) {
  $optional_modules = array_filter($form_state->getValue('optional_modules'));
  \Drupal::state()->set('blogcomposer_install_optional_modules', $optional_modules);
  \Drupal::state()->set('blogcomposer_install_demo_content', $form_state->getValue('demo_content'));
}

/**
 * Installs required modules via a batch process.
 *
 * @param array $install_state
 *   An array of information about the current installation state.
 *
 * @return array
 *   The batch definition.
 */
function blogcomposer_install_profile_modules(array &$install_state) {

  $files = system_rebuild_module_data();

  $modules = [
    'blogcomposer_core' => 'blogcomposer_core',
    'blogcomposer_user' => 'blogcomposer_user',
    'blogcomposer_group' => 'blogcomposer_group',
    'blogcomposer_event' => 'blogcomposer_event',
    'blogcomposer_topic' => 'blogcomposer_topic',
    'blogcomposer_profile' => 'blogcomposer_profile',
    'blogcomposer_editor' => 'blogcomposer_editor',
    'blogcomposer_comment' => 'blogcomposer_comment',
    'blogcomposer_post' => 'blogcomposer_post',
    'blogcomposer_page' => 'blogcomposer_page',
    'blogcomposer_search' => 'blogcomposer_search',
    'blogcomposer_activity' => 'blogcomposer_activity',
    'blogcomposer_follow_content' => 'blogcomposer_follow_content',
    'blogcomposer_mentions' => 'blogcomposer_mentions',
    'blogcomposer_font' => 'blogcomposer_font',
    'blogcomposer_like' => 'blogcomposer_like',
    'blogcomposer_post_photo' => 'blogcomposer_post_photo',
    'blogcomposer_swiftmail' => 'blogcomposer_swiftmail',
  ];
  $blogcomposer_modules = $modules;
  // Always install required modules first. Respect the dependencies between
  // the modules.
  $required = [];
  $non_required = [];

  // Add modules that other modules depend on.
  foreach ($modules as $module) {
    if ($files[$module]->requires) {
      $module_requires = array_keys($files[$module]->requires);
      // Remove the blogcomposer modules from required modules.
      $module_requires = array_diff_key($module_requires, $blogcomposer_modules);
      $modules = array_merge($modules, $module_requires);
    }
  }
  $modules = array_unique($modules);
  // Remove the blogcomposer modules from to install modules.
  $modules = array_diff_key($modules, $blogcomposer_modules);
  foreach ($modules as $module) {
    if (!empty($files[$module]->info['required'])) {
      $required[$module] = $files[$module]->sort;
    }
    else {
      $non_required[$module] = $files[$module]->sort;
    }
  }
  arsort($required);

  $operations = [];
  foreach ($required + $non_required + $blogcomposer_modules as $module => $weight) {
    $operations[] = [
      '_blogcomposer_install_module_batch',
      [[$module], $module],
    ];
  }

  $batch = [
    'operations' => $operations,
    'title' => t('Install Open blogcomposer modules'),
    'error_message' => t('The installation has encountered an error.'),
  ];
  return $batch;
}

/**
 * Final setup of blogcomposer profile.
 *
 * @param array $install_state
 *   The install state.
 *
 * @return array
 *   Batch settings.
 */
function blogcomposer_final_site_setup(array &$install_state) {
  // Clear all status messages generated by modules installed in previous step.
  drupal_get_messages('status', TRUE);

  // There is no content at this point.
  node_access_needs_rebuild(FALSE);

  $batch = [];

  $blogcomposer_optional_modules = \Drupal::state()->get('blogcomposer_install_optional_modules');
  foreach ($blogcomposer_optional_modules as $module => $module_name) {
    $batch['operations'][] = [
      '_blogcomposer_install_module_batch',
      [[$module], $module_name],
    ];
  }
  $demo_content = \Drupal::state()->get('blogcomposer_install_demo_content');
  if ($demo_content === 1) {
    $batch['operations'][] = [
      '_blogcomposer_install_module_batch',
      [['blogcomposer_demo'], 'blogcomposer_demo'],
    ];

    // Generate demo content.
    $demo_content_types = [
      'file' => t('files'),
      'user' => t('users'),
      'group' => t('groups'),
      'topic' => t('topics'),
      'event' => t('events'),
      'event_enrollment' => t('event enrollments'),
      'post' => t('posts'),
      'comment' => t('comments'),
      'like' => t('likes'),
      // @todo Add 'event_type' if module is enabled.
    ];
    foreach ($demo_content_types as $demo_type => $demo_description) {
      $batch['operations'][] = [
        '_blogcomposer_add_demo_batch',
        [$demo_type, $demo_description],
      ];
    }

    // Uninstall blogcomposer_demo.
    $batch['operations'][] = [
      '_blogcomposer_uninstall_module_batch',
      [['blogcomposer_demo'], 'blogcomposer_demo'],
    ];
  }

  // Add some finalising steps.
  $final_batched = [
    'profile_weight' => t('Set weight of profile.'),
    'router_rebuild' => t('Rebuild router.'),
    'trigger_sapi_index' => t('Index search'),
    'cron_run' => t('Run cron.'),
    'import_optional_config' => t('Import optional configuration'),
  ];
  foreach ($final_batched as $process => $description) {
    $batch['operations'][] = [
      '_blogcomposer_finalise_batch',
      [$process, $description],
    ];
  }

  return $batch;
}

/**
 * Install the theme.
 *
 * @param array $install_state
 *   The install state.
 */
function blogcomposer_theme_setup(array &$install_state) {
  // Clear all status messages generated by modules installed in previous step.
  drupal_get_messages('status', TRUE);

  // Also install improved theme settings & color module, because it improves
  // the blogcomposer blue theme settings page.
  $modules = ['color'];
  \Drupal::service('module_installer')->install($modules);

  $themes = ['blogcomposerblue'];
  \Drupal::service('theme_handler')->install($themes);

  \Drupal::configFactory()
    ->getEditable('system.theme')
    ->set('default', 'blogcomposerblue')
    ->save();

  // Ensure that the install profile's theme is used.
  // @see _drupal_maintenance_theme()
  \Drupal::service('theme.manager')->resetActiveTheme();

  $modules = ['improved_theme_settings'];
  \Drupal::service('module_installer')->install($modules);
}

/**
 * Performs final installation steps and displays a 'finished' page.
 *
 * @param array $install_state
 *   An array of information about the current installation state.
 *
 * @see install_finished()
 */
function blogcomposer_install_finished(array &$install_state) {
  // Clear all status messages generated by modules installed in previous step.
  drupal_get_messages('status', TRUE);

  if ($install_state['interactive']) {
    // Load current user and perform final login tasks.
    // This has to be done after drupal_flush_all_caches()
    // to avoid session regeneration.
    $account = User::load(1);
    user_login_finalize($account);
  }
}

/**
 * Implements callback_batch_operation().
 *
 * Performs batch installation of modules.
 */
function _blogcomposer_install_module_batch($module, $module_name, &$context) {
  set_time_limit(0);
  \Drupal::service('module_installer')->install($module);
  $context['results'][] = $module;
  $context['message'] = t('Install %module_name module.', ['%module_name' => $module_name]);
}

/**
 * Implements callback_batch_operation().
 *
 * Performs batch uninstallation of modules.
 */
function _blogcomposer_uninstall_module_batch($module, $module_name, &$context) {
  set_time_limit(0);
  \Drupal::service('module_installer')->uninstall($module);
  $context['results'][] = $module;
  $context['message'] = t('Uninstalled %module_name module.', ['%module_name' => $module_name]);
}

/**
 * Implements callback_batch_operation().
 *
 * Performs batch demo content generation.
 */
function _blogcomposer_add_demo_batch($demo_type, $demo_description, &$context) {
  set_time_limit(0);

  $num_created = 0;

  $content_types = [$demo_type];
  $manager = \Drupal::service('plugin.manager.demo_content');
  $plugins = $manager->createInstances($content_types);

  /** @var \Drupal\blogcomposer_demo\DemoContentInterface $plugin */
  foreach ($plugins as $plugin) {
    $plugin->createContent();
    $num_created = $plugin->count();
  }

  $context['results'][] = $demo_type;
  $context['message'] = t('Generated %num %demo_description.', ['%num' => $num_created, '%demo_description' => $demo_description]);
}

/**
 * Implements callback_batch_operation().
 *
 * Performs batch finalising.
 */
function _blogcomposer_finalise_batch($process, $description, &$context) {

  switch ($process) {
    case 'profile_weight':
      $profile = drupal_get_profile();

      // Installation profiles are always loaded last.
      module_set_weight($profile, 1000);
      break;

    case 'router_rebuild':
      // Build the router once after installing all modules.
      // This would normally happen upon KernelEvents::TERMINATE, but since the
      // installer does not use an HttpKernel, that event is never triggered.
      \Drupal::service('router.builder')->rebuild();
      break;

    case 'trigger_sapi_index':
      $indexes = Index::loadMultiple();
      /** @var \Drupal\search_api\Entity\Index $index */
      foreach ($indexes as $index) {
        $index->reindex();
      }
      break;

    case 'cron_run':
      // Run cron to populate update status tables (if available) so that users
      // will be warned if they've installed an out of date Drupal version.
      // Will also trigger indexing of profile-supplied content or feeds.
      \Drupal::service('cron')->run();
      break;

    case 'import_optional_config':
      // We need to import all the optional configuration as well, since
      // this is not supported by Drupal Core installation profiles yet.
      /** @var \Drupal\features\FeaturesAssignerInterface $assigner */
      $assigner = \Drupal::service('features_assigner');

      $bundle = $assigner->applyBundle('blogcomposer');
      if ($bundle->getMachineName() === 'blogcomposer') {
        $current_bundle = $bundle;

        /** @var \Drupal\features\FeaturesManagerInterface $manager */
        $manager = \Drupal::service('features.manager');
        $packages = $manager->getPackages();

        $packages = $manager->filterPackages($packages, $current_bundle->getMachineName());

        $options = [];
        foreach ($packages as $package) {
          if ($package->getStatus() != FeaturesManagerInterface::STATUS_NO_EXPORT) {
            $missing = $manager->reorderMissing($manager->detectMissing($package));
            $overrides = $manager->detectOverrides($package, TRUE);
            if (!empty($overrides) || !empty($missing)) {
              $options += [
                $package->getMachineName() => [],
              ];
            }
          }
        }

        /** @var \Drupal\features\FeaturesManagerInterface $manager */
        $manager = \Drupal::service('features.manager');
        $packages = $manager->getPackages();
        $packages = $manager->filterPackages($packages, 'blogcomposer');
        $overridden = [];

        foreach ($packages as $package) {
          $overrides = $manager->detectOverrides($package);
          $missing = $manager->detectMissing($package);
          if ((!empty($missing) || !empty($overrides)) && ($package->getStatus() == FeaturesManagerInterface::STATUS_INSTALLED)) {
            $overridden[] = $package->getMachineName();
          }
        }
        if (!empty($overridden)) {
          blogcomposer_features_import($overridden);
        }

      }
      break;
  }

  $context['results'][] = $process;
  $context['message'] = $description;
}

/**
 * Imports module config into the active store.
 *
 * @see drush_features_import()
 */
function blogcomposer_features_import($args) {

  /** @var \Drupal\features\FeaturesManagerInterface $manager */
  $manager = \Drupal::service('features.manager');
  /** @var \Drupal\config_update\ConfigRevertInterface $config_revert */
  $config_revert = \Drupal::service('features.config_update');

  // Parse list of arguments.
  $modules = [];
  foreach ($args as $arg) {
    $arg = explode(':', $arg);
    $module = array_shift($arg);
    $component = array_shift($arg);

    if (isset($module)) {
      if (empty($component)) {
        // If we received just a feature name, this means that we need all of
        // its components.
        $modules[$module] = TRUE;
      }
      elseif ($modules[$module] !== TRUE) {
        if (!isset($modules[$module])) {
          $modules[$module] = [];
        }
        $modules[$module][] = $component;
      }
    }
  }

  // Process modules.
  foreach ($modules as $module => $components_needed) {

    /** @var \Drupal\features\Package $feature */
    $feature = $manager->loadPackage($module, TRUE);
    if (empty($feature)) {
      return;
    }

    if ($feature->getStatus() != FeaturesManagerInterface::STATUS_INSTALLED) {
      return;
    }

    // Only revert components that are detected to be Overridden.
    $components = $manager->detectOverrides($feature);
    $missing = $manager->reorderMissing($manager->detectMissing($feature));
    // Be sure to import missing components first.
    $components = array_merge($missing, $components);

    if (!empty($components_needed) && is_array($components_needed)) {
      $components = array_intersect($components, $components_needed);
    }

    if (!empty($components)) {
      $config = $manager->getConfigCollection();
      foreach ($components as $component) {
        if (!isset($config[$component])) {
          // Import missing component.
          /** @var array $item */
          $item = $manager->getConfigType($component);
          $type = ConfigurationItem::fromConfigStringToConfigType($item['type']);
          $config_revert->import($type, $item['name_short']);
        }
        else {
          // Revert existing component.
          /** @var \Drupal\features\ConfigurationItem $item */
          $item = $config[$component];
          $type = ConfigurationItem::fromConfigStringToConfigType($item->getType());
          $config_revert->revert($type, $item->getShortName());
        }
      }
    }
  }
}
