<?php

namespace Drupal\social_post_twitter\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Core\Logger\LoggerChannelFactoryInterface;
use Drupal\social_api\Plugin\NetworkManager;
use Drupal\social_post\SocialPostDataHandler;
use Drupal\social_post\SocialPostManager;
use Drupal\social_post_twitter\TwitterPostAuthManager;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Zend\Diactoros\Response\RedirectResponse;
use Symfony\Component\HttpFoundation\RequestStack;

/**
 * Manages requests to Twitter.
 */
class TwitterPostController extends ControllerBase {

  /**
   * The network plugin manager.
   *
   * @var \Drupal\social_api\Plugin\NetworkManager
   */
  private $networkManager;

  /**
   * The LinkedIn authentication manager.
   *
   * @var \Drupal\social_post_twitter\TwitterPostAuthManager
   */
  private $providerManager;

  /**
   * The Social Auth Data Handler.
   *
   * @var \Drupal\social_post\SocialPostDataHandler
   */
  private $dataHandler;

  /**
   * Used to access GET parameters.
   *
   * @var \Symfony\Component\HttpFoundation\RequestStack
   */
  private $request;

  /**
   * The logger channel.
   *
   * @var \Drupal\Core\Logger\LoggerChannelFactoryInterface
   */
  protected $loggerFactory;

  /**
   * The social post manager.
   *
   * @var \Drupal\social_post\SocialPostManager
   */
  protected $postManager;

  /**
   * TWitterAuthController constructor.
   *
   * @param \Drupal\social_api\Plugin\NetworkManager $network_manager
   *   Used to get an instance of social_post_twitter network plugin.
   * @param \Drupal\social_post\SocialPostManager $post_manager
   *   Manages user login/registration.
   * @param \Drupal\social_post_twitter\TwitterPostAuthManager $provider_manager
   *   Used to manage authentication methods.
   * @param \Symfony\Component\HttpFoundation\RequestStack $request
   *   Used to access GET parameters.
   * @param \Drupal\social_post\SocialPostDataHandler $data_handler
   *   SocialAuthDataHandler object.
   * @param \Drupal\Core\Logger\LoggerChannelFactoryInterface $logger_factory
   *   Used for logging errors.
   */
  public function __construct(NetworkManager $network_manager,
                              SocialPostManager $post_manager,
                              TwitterPostAuthManager $provider_manager,
                              RequestStack $request,
                              SocialPostDataHandler $data_handler,
                              LoggerChannelFactoryInterface $logger_factory) {

    $this->networkManager = $network_manager;
    $this->postManager = $post_manager;
    $this->providerManager = $provider_manager;
    $this->request = $request;
    $this->dataHandler = $data_handler;
    $this->loggerFactory = $logger_factory;

    $this->postManager->setPluginId('social_post_twitter');

    // Sets session prefix for data handler.
    $this->dataHandler->setSessionPrefix('social_post_twitter');
  }

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container) {
    return new static(
      $container->get('plugin.network.manager'),
      $container->get('social_post.post_manager'),
      $container->get('twitter_post.auth_manager'),
      $container->get('request_stack'),
      $container->get('social_post.data_handler'),
      $container->get('logger.factory')
    );
  }

  /**
   * Redirects user to Twitter for authentication.
   *
   * @return \Zend\Diactoros\Response\RedirectResponse
   *   Redirects to Twitter.
   *
   * @throws \Abraham\TwitterOAuth\TwitterOAuthException
   */
  public function redirectToProvider() {
    /* @var \Drupal\social_post_twitter\Plugin\Network\TwitterPost $network_plugin */
    $network_plugin = $this->networkManager->createInstance('social_post_twitter');

    /* @var \Abraham\TwitterOAuth\TwitterOAuth $connection */
    $connection = $network_plugin->getSdk();

    $request_token = $connection->oauth('oauth/request_token', ['oauth_callback' => $network_plugin->getOauthCallback()]);

    // Saves the request token values in session.
    $this->providerManager->setOauthToken($request_token['oauth_token']);
    $this->providerManager->setOauthTokenSecret($request_token['oauth_token_secret']);

    // Generates url for authentication.
    $url = $connection->url('oauth/authorize', ['oauth_token' => $request_token['oauth_token']]);

    return new RedirectResponse($url);
  }

  /**
   * Callback function for the authentication process.
   *
   * @throws \Abraham\TwitterOAuth\TwitterOAuthException
   */
  public function callback() {
    // Checks if user denied authorization.
    if ($this->request->getCurrentRequest()->get('denied')) {
      drupal_set_message($this->t('You could not be authenticated.'), 'error');
      return $this->redirect('entity.user.edit_form', ['user' => $this->currentUser->id()]);
    }

    $oauth_token = $this->providerManager->getOauthToken();
    $oauth_token_secret = $this->providerManager->getOauthTokenSecret();

    /* @var \Abraham\TwitterOAuth\TwitterOAuth $connection */
    $connection = $this->networkManager->createInstance('social_post_twitter')->getSdk2($oauth_token, $oauth_token_secret);

    // Gets the permanent access token.
    $access_token = $connection->oauth('oauth/access_token', ['oauth_verifier' => $this->providerManager->getOauthVerifier()]);
    $connection = $this->networkManager->createInstance('social_post_twitter')->getSdk2($access_token['oauth_token'], $access_token['oauth_token_secret']);

    // Gets user information.
    $params = [
      'include_email' => 'true',
      'include_entities' => 'false',
      'skip_status' => 'true',
    ];
    $profile = $connection->get("account/verify_credentials", $params);

    if (!$this->postManager->checkIfUserExists($profile->id)) {
      $this->postManager->addRecord($profile->name, $profile->id, json_encode($access_token));
      drupal_set_message($this->t('Account added successfully.'), 'status');
    }
    else {
      drupal_set_message($this->t('You have already authorized to post on behalf of this user.'), 'warning');
    }

    return $this->redirect('entity.user.edit_form', ['user' => $this->postManager->getCurrentUser()]);
  }

}
