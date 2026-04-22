<?php
// Default Language
$lang = 'en';

// If lang parameter is set, use it
if (isset($_GET['lang'])) {
  $lang = $_GET['lang'];
}
?>

<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <title>corpnetblog</title>
  </head>
  <body>
    <h1>CORP NET BLOG</h1>

    <form method="GET" action="">
      <label for="lang">Choose language:</label>
      <select name="lang" id="lang" onchange="this.form.submit()">
        <option value="en">English</option>
        <option value="es">Spanish</option>
        <option value="fr">French</option>
      </select>
    </form>
    <hr>
    <div>
      <?php
        //Load language file
        include "./languages/$lang";
      ?>
    </div>
  </body>
</html>
