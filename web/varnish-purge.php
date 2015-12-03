<?php

  require_once ("app/Mage.php");
  umask(0);
  Mage::app();
  Mage::getSingleton('core/session',array('name'=>'adminhtml'));
  $auth = true;
  if (!($user = Mage::getSingleton('admin/session')) || is_null($user->getUser())) {
    header('HTTP/1.0 403 Forbidden');
    $auth = false;
  }

  $response = false;
  $mseNodes = array('lb1.dh1.cX.sonassihosting.com');
  $postNodes = (is_array($_POST['node'])) ? $_POST['node'] : array();

  if (count($postNodes) && $auth) {
    $curlData = false;
    foreach ($postNodes as $mseNode) {
      $url = (!empty($_POST['url'])) ? $_POST['url'] : 'http://'.$mseNode;
      $url = (!preg_match('#^https?://#', $url)) ? 'http://'.$url : $url;

      $uri = (!empty($_POST['uri'])) ? $_POST['uri'] : '/.*';
      $uri = '/'.preg_replace('#^/+#', '', $uri);

      $components = parse_url($url);

      $ch = curl_init();
      curl_setopt($ch, CURLOPT_URL, sprintf('%s://%s%s', $components['scheme'], $mseNode, $uri));
      curl_setopt($ch, CURLOPT_HTTPHEADER, array('Host: '. $components['host']));
      curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'PURGE');
      curl_setopt($ch, CURLOPT_HEADER, true);
      curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
      curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 0);
      curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, 0);

      $curlData .= sprintf("Purging (%s) - %s://%s%s\n", $mseNode, $components['scheme'], $components['host'], $uri);
      $curlData .= curl_exec($ch);
    }

    $response = sprintf("<textarea>%s</textarea>", $curlData);
  }

?>
<html>
  <head>
    <title>
      Varnish Purge Interactive
    </title>
    <link rel="shortcut icon" href="/favicon.ico" />
    <style>
      body {margin:0 auto; width:1000px; background: none repeat scroll 0 0 #DDDDDD;padding-top:5%;text-align:center;font: 13px/1.5 Monaco,Consolas,"Andale Mono","DejaVu Sans Mono",monospace;}
      textarea {height:200px;}
      input, textarea {width:100%; padding:5px; font: 13px/1.5 Monaco,Consolas,"Andale Mono","DejaVu Sans Mono",monospace;}
      label {float:left;}
      .mse {float:left; width:30%;}
      .clear {clear:both;}
      .btn {width:50%; float:left;}
    </style>
  </head>
  <body>
    <?php if ($auth): ?>
      <?php if ($response) echo $response; ?>
      <form method="POST" action="<?php echo $_SERVER['PHP_SELF']; ?>">
        <input type="text" name="url" value="<?php echo (!empty($_POST['url'])) ? $_POST['url'] : ''; ?>" placeholder="Default: http://.*" />
        <input type="text" name="uri" value="<?php echo (!empty($_POST['uri'])) ? $_POST['uri'] : ''; ?>" placeholder="Default: /.*" />
        <input type="hidden" name="purge" value="1" />
        <br /><br />
        <?php foreach ($mseNodes as $mseNode): ?>
          <input <?php echo (in_array($mseNode, $postNodes)) ? 'checked="checked"' : ''; ?> type="checkbox" name="node[]" value="<?php echo $mseNode; ?>" class="mse" id="mse-<?php echo $mseNode; ?>" /><label for="mse-<?php echo $mseNode; ?>"><?php echo $mseNode; ?></label>
          <br class="clear" />
        <?php endforeach; ?>
        <br />
        <input type="reset" class="btn" value="Reset Form">
        <input type="submit" class="btn" value="Purge">
      </form>
    <?php else: ?>
      <h3>Forbidden</h3>
    <?php endif; ?>
  </body>
</html>
