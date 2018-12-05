<?php

namespace Drupal\social_post_twitter\Plugin\RulesAction;

use Drupal\Core\Plugin\ContainerFactoryPluginInterface;
use Drupal\Core\Session\AccountInterface;
use Drupal\rules\Core\RulesActionBase;
use Drupal\social_post\SocialPostManager;
use Drupal\social_post_twitter\Plugin\Network\TwitterPostInterface;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Provides a 'Tweet' action.
 *
 * @RulesAction(
 *   id = "social_post_twitter_tweet",
 *   label = @Translation("Tweet"),
 *   category = @Translation("Social Post"),
 *   context = {
 *     "status" = @ContextDefinition("string",
 *       label = @Translation("Tweet content"),
 *       description = @Translation("Specifies the status to post.")
 *     )
 *   }
 * )
 */
class Tweet extends RulesActionBase implements ContainerFactoryPluginInterface {

  /**
   * The twitter post network plugin.
   *
   * @var \Drupal\social_post_twitter\Plugin\Network\TwitterPostInterface
   */
  protected $post;

  /**
   * The social post twitter entity storage.
   *
   * @var \Drupal\social_post\SocialPostManager
   */
  protected $postManager;

  /**
   * The current user.
   *
   * @var \Drupal\Core\Session\AccountInterface
   */
  protected $currentUser;

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container, array $configuration, $plugin_id, $plugin_definition) {
    /* @var \Drupal\social_post_twitter\Plugin\Network\TwitterPost $twitter_post*/
    $twitter_post = $container->get('plugin.network.manager')->createInstance('social_post_twitter');

    return new static(
      $configuration,
      $plugin_id,
      $plugin_definition,
      $twitter_post,
      $container->get('social_post.post_manager'),
      $container->get('current_user')
    );
  }

  /**
   * Tweet constructor.
   *
   * @param array $configuration
   *   A configuration array containing information about the plugin instance.
   * @param string $plugin_id
   *   The plugin ID for the plugin instance.
   * @param mixed $plugin_definition
   *   The plugin implementation definition.
   * @param \Drupal\social_post_twitter\Plugin\Network\TwitterPostInterface $twitter_post
   *   The twitter post network plugin.
   * @param \Drupal\social_post\SocialPostManager $post_manager
   *   The social post manager.
   * @param \Drupal\Core\Session\AccountInterface $current_user
   *   The current user.
   */
  public function __construct(array $configuration,
                              $plugin_id,
                              $plugin_definition,
                              TwitterPostInterface $twitter_post,
                              SocialPostManager $post_manager,
                              AccountInterface $current_user) {

    parent::__construct($configuration, $plugin_id, $plugin_definition);

    $this->post = $twitter_post;
    $this->postManager = $post_manager;
    $this->currentUser = $current_user;

    $this->postManager->setPluginId('social_post_twitter');

  }

  /**
   * {@inheritdoc}
   */
  public function execute() {
    $accounts = $this->postManager->getAccountsByUserId('social_post_twitter', $this->currentUser->id());
    $status = $this->getContextValue('status');

    /* @var \Drupal\social_post\Entity\SocialPost $account */
    foreach ($accounts as $account) {
      $access_token = json_decode($this->postManager->getToken($account->getProviderUserId()), TRUE);
      $this->post->doPost($access_token['oauth_token'], $access_token['oauth_token_secret'], $status);
    }
  }

}
