<?php

    require_once 'app/Mage.php';
    Mage::app();
    Mage::app()->setCurrentStore(Mage_Core_Model_App::ADMIN_STORE_ID);

    class MagePerftestAdmin
    {

        const USERNAME  = 'sonassi_emulate';
        const EMAIL     = 'emulate@example.com';
        const ROLENAME  = 'Emulate';
        const FIRSTNAME = 'Sonassi';
        const LASTNAME  = 'Emulate';
        const COOKIEFILE = '/tmp/cookie';

        private $_password;
        private $_adminLoginUrl;
        private $_formKey;
        private $_navigation;

        public function __construct($urls)
        {
            if (!count($urls))
                $this->usage();

            @unlink(self::COOKIEFILE);
            $this->loginAdmin();
            $this->output("--", null);
            $this->runTest($urls);
            $this->output("--", null);
            $this->deleteAdmin();
        }

        private function runTest($urls)
        {
            foreach ($urls as $url) {
                if ($urlWithKey = $this->getNavLink($url)) {
                    $st = microtime(true);
                    $result = $this->curl($urlWithKey);
                    preg_match('#<title>(.+?)</title>#mis', $result, $matches);
                    $et = microtime(true);
                    $this->output(sprintf("%0.3fs   %s (%s)", $et-$st, $url, $matches[1]), 'results');
                } else {
                    $this->output(sprintf('Could not load URL (%s)', $url));
                }
            }
        }

        private function usage()
        {
echo <<<EOF
mage-perftest-admin.php Usage:

mage-perftest-admin.php [url_match] [url_match] .. [url_match]

  url_match       A partial of the Magento admin URL you want to hit. The script uses this string to search
                  through the Magento admin navigation to find the appropriate URL.

EOF;
            exit(0);
        }

        private function getUrl($url)
        {
            $url = str_replace('mage-perftest-admin.php', 'index.php', Mage::getUrl($url));
            return $url;
        }

        private function getNavLink($match)
        {
            if (preg_match('#<a href="(.+?'.$match.'[^"]+)"#', $this->_navigation, $matches)) {
                return $matches[1];
            }
            return false;
        }

        private function loginAdmin()
        {
            $this->createAdmin();

            $this->output('Creating session');
            $this->curl($this->_adminLoginUrl, array('cookiejar' => self::COOKIEFILE));

            $this->output('Logging in');
            if ($formData = $this->getFormData($this->curl($this->_adminLoginUrl))) {
                if (empty($formData['action']))
                    $formData['action'] = $this->_adminLoginUrl;

                $url = $formData['action'];
                unset($formData['action']);
                $formData['login[username]'] = self::USERNAME;
                $formData['login[password]'] = $this->_password;

                $result = $this->curl($url, array('post' => $formData, 'cookiejar' => self::COOKIEFILE));
                preg_match('#<title>(.+?)</title>#mis', $result, $matches);

                $this->_navigation = preg_match('#<!-- menu start -->(.+?)<!-- menu end -->#mis', $result, $matches);
                $this->_navigation = $matches[0];

                return $this->output('Login successful');
            }

            $this->output('Failed to login', 'error');
        }

        private function output($msg, $level = 'notice')
        {
            printf("[%s]: %s\n", $level, $msg);
            if ($level == 'error')
                exit(1);
            return true;
        }

        private function getFormData($html)
        {
            if (preg_match_all('/form method.+?action="([^"]+)?".+?name="form_key".+?value="([^"]+)"/mis', $html, $matches)) {
                $result = array('action' => $matches[1][0],
                                'form_key' => $matches[2][0]);

                return $result;
            }
            return false;
        }

        private function deleteAdmin()
        {
            $user = Mage::getModel('admin/user');
            $user->loadByUsername(self::USERNAME)->delete();
            $this->output("Deleted admin user");
        }

        private function createAdmin()
        {
            $this->output('Creating admin user');
            $this->_password = substr(str_shuffle('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'), 0, 10);

            $user = Mage::getModel('admin/user');

            if ($user->loadByUsername(self::USERNAME)->getUsername()) {
                $user = $user->loadByUsername(self::USERNAME);
            } else {
                $user->setData(array(
                    'username' => self::USERNAME,
                    'email' => self::EMAIL,
                    'firstname' => self::FIRSTNAME,
                    'lastname'  => self::LASTNAME,
                  ));
            }

            $user->setData(array_merge($user->getData(), array(
                'password' => $this->_password,
                'is_active' => 1,
            )));

            $user->save();

            $role = Mage::getModel("admin/roles");
            $roleId = false;

            $roles = $role->getCollection();
            foreach($roles as $adminRole) {
              if ($adminRole->getRoleName() == self::ROLENAME) {
                $role = $adminRole;
                break;
              }
            }

            $role->setName(self::ROLENAME)
                 ->setRoleType('G')
                 ->save();

            Mage::getModel("admin/rules")
                ->setRoleId($role->getId())
                ->setResources(array("all"))
                ->saveRel();

            $user->setRoleIds(array($role->getId()))
                 ->setRoleUserId($user->getUserId())
                 ->saveRelations();

            $this->_adminLoginUrl = $this->getUrl('adminhtml');
        }

        private function curl($url, $z = null)
        {
            $ch =  curl_init();

            $useragent = isset($z['useragent']) ? $z['useragent'] : 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:10.0.2) Gecko/20100101 Firefox/10.0.2';

            curl_setopt($ch, CURLOPT_URL, $url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_AUTOREFERER, true);
            curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
            curl_setopt($ch, CURLOPT_POST, isset($z['post']));
            curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 0);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, 0);

            if (isset($z['post']))
                curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($z['post']));
            if (isset($z['refer']))
                curl_setopt($ch, CURLOPT_REFERER, $z['refer']);
            if (isset($z['ssl_version']))
                curl_setopt($ch, CURLOPT_SSLVERSION, $z['ssl_version']);
            if (isset($z['cookiejar']))
                curl_setopt($ch, CURLOPT_COOKIEJAR, $z['cookiejar']);

            curl_setopt($ch, CURLOPT_USERAGENT, $useragent);
            curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, (isset($z['timeout']) ? $z['timeout'] : 5 ));
            curl_setopt($ch, CURLOPT_COOKIEFILE, self::COOKIEFILE);

            if (isset($z['curlopt']) && is_array($z['curlopt'])) {
                foreach ($z['curlopt'] as $key => $value)
                    curl_setopt($ch, $key, $value);
            }

            if (!($result = curl_exec($ch))) {
                $result = curl_error($ch);

                if (preg_match('/1112/', $result) && !isset($z['ssl_version'])) {
                    curl_close($ch);
                    $z['ssl_version'] = 1;
                    return $this->curl($url, $z);
                }
            }

            curl_close($ch);
            return $result;
        }

    }

    array_shift($argv);
    $magePerftestAdmin = new MagePerftestAdmin($argv);

