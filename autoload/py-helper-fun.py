def func_info_x234(thing, completion_types):
  """helper function for Vim repl completion"""
  def toList(name, thing, type):
      doc = "_"
      arity = 0
      spec = []
      try:
        doc = thing.__doc__
      except Exception, e:
        doc = "-"
      try:
        spec = inspect.getargspec(thing)
        spec = [spec.args, spec.varargs, spec.keywords, spec.defaults.__str__()]
      except Exception, e:
        spec = []
      return [type, name, doc, spec] 
  result = []
  if completion_types.__contains__("dict"):
    for d in thing.keys():
      result.append(toList(d, thing[d], 'key'))
  elif completion_types.__contains__("dir"):
    for d in dir(thing):
      result.append(toList(d, getattr(thing,d), "dir"))
  return result
