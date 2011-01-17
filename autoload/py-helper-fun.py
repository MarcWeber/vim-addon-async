def func_info_x234(thing, completion_types):
  """helper function for Vim repl completion"""
  def toVim(thing):
    if type(thing) == type([]):
      return "[%s]" % (",".join([toVim(x) for x in thing]))
    elif type(thing) == type(""):
      return '"%s"' % thing.replace('\\','\\\\').replace('"', '\\"').replace("\n", "\\n")
    else:
      return str(thing)
  def toList(name, item, source):
      doc = "_"
      arity = 0
      spec = []
      try:
        doc = item.__doc__
      except Exception, e:
        doc = "-"
      try:
        spec = inspect.getargspec(item)
        spec = [spec.args, spec.varargs, spec.keywords, spec.defaults.__str__()]
      except Exception, e:
        spec = []
      type_ = "-"
      try:
        type_ = type(item)
      except Exception, e:
        type_ = "-"
      return [source, name, doc, spec, str(type_)] 
  result = []
  if completion_types.__contains__("dict"):
    for d in thing.keys():
      result.append(toList(d, thing[d], 'key'))
  elif completion_types.__contains__("dir"):
    for d in dir(thing):
      result.append(toList(d, getattr(thing, d), "dir"))
  return toVim(result)
