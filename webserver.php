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
    <style>
      .title {
        background-color: black;
        padding: 10px;
        width: 100%;
      }
      .title h1 {
        color: cyan;
        margin: 0;
      }
      .chooselang {
        padding: 10px;
      }
    </style>
  </head>
  <body>
    <div class="title">
      <h1>CORP NET BLOG</h1>
    </div>
    <div class="chooselang">
      <form method="GET" action="">
        <label for="lang">Choose language:</label>
        <select name="lang" id="lang" onchange="this.form.submit()">
          <option value="en" <?php if ($lang == 'en') echo 'selected'; ?>>English</option>
          <option value="es" <?php if ($lang == 'es') echo 'selected'; ?>>Spanish</option>
          <option value="fr" <?php if ($lang == 'fr') echo 'selected'; ?>>French</option>
        </select>
      </form>
    </div>
    <hr>
    <div>
      <?php
        //Load language file
        include "./languages/$lang";
      ?>
    </div>
  </body>
</html>
