<?php
function echo_completions($thing){
  $results = array();
  if (is_array($thing)) {
    foreach (array_keys($thing) as $key) {
      $results[] = array('name' => "['".$key."']", 'description' => '');
    }
  }
  elseif (is_object($thing)){
    foreach (get_object_vars($thing) as $key => $object_var) {
      $results[] = array('name' => $key, 'description' => 'obj var');
    }

    $r = new ReflectionClass($thing);
    if ($r){
      if (is_array($async_r->getConstants))
        foreach ($async_r->getConstants as $c => $value) {
          $results[] = array('name' => $c, 'description' => 'constant = '.$value);
        }

      if (is_array($r->getMethods()))
        foreach ($r->getMethods() as $method) {
          $results[] = array(
            'name' => '->'.$method->name.'(',
            'description' => 'class : '.$method->class
          );
        }
     }
  }
  echo 'COMPLETION:'.json_encode($results)."\n";
}
