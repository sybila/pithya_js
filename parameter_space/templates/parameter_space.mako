<%!
  import os
  import glob
  import re
  import json
  import timeit
  from itertools import chain
  from routes import url_for
  from asteval import Interpreter

  prefix = url_for("/")
  path = os.getcwd()
  aeval = Interpreter()
  debug = False
  
%>
<%def name="save_button( text='Save' )">
<%
    # still a GET
    url_for_args = {
        'controller'    : 'visualization',
        'action'        : 'saved',
        'type'          : visualization_name,
        'title'         : title,
        'config'        : h.dumps( config )
    }
    # save to existing visualization
    if visualization_id:
        url_for_args[ 'id' ] = visualization_id
%>
    <form action="${h.url_for( **url_for_args )}" method="post"><input type="submit" value="${text}" /></form>
</%def>
<%
  app_root = "config/plugins/visualizations/"+visualization_name+"/"
  
  ## list of string lines of input bio file
  data = ''.join(list(hda.datatype.dataprovider(
    hda, 
    'line', 
    strip_lines=True, 
    strip_newlines=True )))
  
  results = json.loads(data)
  
  # print(results.keys())
  ## [u'parameter_values', u'parameters', u'variables', u'results', u'states', u'parameter_bounds', u'type', u'thresholds']
  
  if results[u'type'] == 'smt':
  
    ## unique name of reduced formulae output file (should be unique for every file from personal history)
    output_data = '/tmp/'+hda.name+".hid_"+str(hda.id)+".id_"+str(hda.hid)+".reduced.json"
    ## if this input were saved before and the output is still in tmp the reduction process will be skipped
    if not os.path.isfile(output_data):
      print("## Reduction needed !!!")

      start_time = timeit.default_timer()
      if debug: print("total init results: "+str(len(results[u'parameter_values'])))
      par_val = {}
      for i in range(0,len(results[u'parameter_values'])):
        
        res = results[u'parameter_values'][i][u'Rexpression']
        if debug and i==0: print(res)
        res = res.replace('ip$','').replace(' ','').replace('!','not').replace('&&','&').replace('&','and').replace('||','|').replace('|','or')
        
        # replacing of numbers: import re
        #                       from asteval import Interpreter  # must be installed via: pip install asteval
        #                       aeval = Interpreter()
        # pattern: rs = re.findall('(?<![_a-zA-Z])(\d+/\d+|\d+)(?![_a-zA-Z])','(x<190/100)and(x>10)') --> ['190/100', '10']
        #          format(aeval(rs[0]),'.2f') -->  1.90
        #          format(aeval(rs[1]),'.2f') --> 10.00
        #          re.sub('(?<![_a-zA-Z0-9./])'+str(rs[0])+'(?![_a-zA-Z0-9./])',format(aeval(rs[0]),'.2f'),'(x<190/100)and(x>10)')
        old_nums = re.findall('(?<![_a-zA-Z])(\d+/\d+|\d+)(?![_a-zA-Z])',res)
        new_nums = [format(aeval(k),'.8f') for k in old_nums]
        for n in range(0,len(old_nums)):
          res = re.sub('(?<![_a-zA-Z0-9./])'+old_nums[n]+'(?![_a-zA-Z0-9./])',new_nums[n],res)
        
        if debug and i==0: print(res)
        
        for p in range(0,len(results['parameters'])):
          par = results['parameters'][p]
          parv = results['parameter_bounds'][p]
          if debug and i==0: print('to replace: '+par+'<='+format(parv[0],'.8f'))
          res = res.replace(par+'<='+format(parv[0],'.8f'),'FALSE').replace(par+'>='+format(parv[0],'.8f'),'TRUE').replace(format(parv[0],'.8f')+'>='+par,'FALSE').replace(format(parv[0],'.8f')+'<='+par,'TRUE')
          res = res.replace(par+'<='+format(parv[1],'.8f'),'TRUE').replace(par+'>='+format(parv[1],'.8f'),'FALSE').replace(format(parv[1],'.8f')+'>='+par,'TRUE').replace(format(parv[1],'.8f')+'<='+par,'FALSE')
        
        if debug and i==0: print(res)
        
        resl = len(res)
        res = res.replace('not(FALSE)','TRUE').replace('not(TRUE)','FALSE')
        while resl != len(res):
          resl = len(res)
          res = res.replace('not(FALSE)','TRUE').replace('not(TRUE)','FALSE')
        
        if debug and i==0: print(res)
        
        res = res.replace('and(TRUE)','').replace('(TRUE)and','').replace('or(FALSE)','').replace('(FALSE)or','')
        
        if debug and i==0: print(res)
        
        par_val[i] = res
      
      ## now we have reduced formulae so we need to remove redundant ones and change indices in results to those new formulae
      par_hash = {}
      done = set()
      uniq = list() # new list of unique formulae
      ui = 0        # index of the last added unique formula
      for k,v in par_val.items():
        if k not in done:
          par_hash[k] = ui
          done.add(k)
          uniq.append(v)
          for k2,v2 in par_val.items(): 
            if k2 not in done and v2 == v:
              # it's another item with different key but the same value
              par_hash[k2] = ui
              done.add(k2)
          ui += 1
            
      # change of values in parameter_values
      results[u'parameter_values'] = uniq
      # chnage of indices in results in the place of parameterisation
      for res in results[u'results']:
        for dat in res[u'data']:
          dat[1] = par_hash[dat[1]]
      
      if debug: print('total final results: '+str(len(uniq)))
      elapsed = timeit.default_timer() - start_time
      if debug: print('time: '+str(elapsed))
      
      ## all lines joined into one structured string (keeping all newlines)
      data_text = json.dumps(results)
      
      f=open(output_data,"w")
      f.write(data_text)
      f.close()
    else:
      print('## Reduction was done before!')
    
    with open(output_data) as f: results = json.loads(f.read())
  
  ## parssing of bio file format to python structures (later used in JS)
  vars =   [str(k) for k in results[u'variables']]
  params = [[str(k), results[u'parameter_bounds'][i][0], results[u'parameter_bounds'][i][1]] for i, k in enumerate(results[u'parameters'])]
  thrs =   dict({str(k) : results[u'thresholds'][i] for i, k in enumerate(results[u'variables'])}, 
                **{str(k) : results[u'parameter_bounds'][i] for i, k in enumerate(results[u'parameters'])})
  
  type = str(results[u'type'])
  states = {k[u'id']: k[u'bounds'] for k in results[u'states'] }
  params_val = [ k.encode('utf-8') for k in results[u'parameter_values'] ] if results['type'] == 'smt' else results['parameter_values']
  ## next line of code will transform results: vector of lists with formula string and data vector of pairs of state and parameterisation indices
  ## into list (indexed by formula string) of data vector of the same pairs but this time state index is actual id of state and not the position of state in the states vector
  results = {str(k[u'formula']): [ [results[u'states'][r[0]][u'id'],r[1]] for r in k[u'data']] for k in results[u'results'] }
  
%>
<html lan"en">
  
  <head>
    <title>Parameter Space</title>
  	<script src="https://d3js.org/d3.v4.js" charset="utf-8"></script>
  	<script src="https://unpkg.com/mathjs@5.3.1/dist/math.min.js" />
    <script type="text/javascript" src="static/js/d3-format/d3-format.min.js"></script>
  	<script type="text/javascript" charset="utf-8">
      // definition of functions used in bio files so there is no need to transorm them 
      function Hillm(x,t,n,b,a) {
        return a+(b-a)*(Math.pow(t,n)/(Math.pow(x,n)+Math.pow(t,n)));
      };
      hillm = Hillm;
      function Hillp(x,t,n,a,b) {
        return a+(b-a)*(Math.pow(x,n)/(Math.pow(x,n)+Math.pow(t,n)));
      };
      hillp = Hillp;
      function Approx(s,ramps) {
        if(s <= ramps[0][0]) return(ramps[0][1])
        if(s >= ramps[ramps.length-1][0]) return(ramps[ramps.length-1][1])
        for(var i = 1, len = ramps.length;  i < len; ++i) {
          a = ramps[i-1]
          b = ramps[i]
          if(s >= a[0] && s <= b[0]) 
            return((b[0]-a[0]) > 0 ? a[1]+(s-a[0])/(b[0]-a[0])*(b[1]-a[1]) : a[1])
        }
      }
      
      // creates one structure containing all data from result.json file for JS code
      window.bio = {'thrs': ${thrs}, 
                    'vars': ${vars}, 
                    'params': ${params}};
      window.result = {'type': "${type}", 
                       'states': ${states}, 
                       'params': ${params_val}, 
                       'map': ${results} };
      //console.log(window.bio);
      //console.log(window.result);
      
      Set.prototype.difference = function(setB) {
          var difference = new Set(this);
          for (var elem of setB) {
              difference.delete(elem);
          }
          return difference;
      };
      
      // Warn if overriding existing method
      if(Array.prototype.equals)
          console.warn("Overriding existing Array.prototype.equals. Possible causes: New API defines the method, there's a framework conflict or you've got double inclusions in your code.");
      // attach the .equals method to Array's prototype to call it on any array
      Array.prototype.equals = function (array) {
          // if the other array is a falsy value, return
          if (!array)
              return false;
      
          // compare lengths - can save a lot of time 
          if (this.length != array.length)
              return false;
      
          for (var i = 0, l=this.length; i < l; i++) {
              // Check if we have nested arrays
              if (this[i] instanceof Array && array[i] instanceof Array) {
                  // recurse into the nested arrays
                  if (!this[i].equals(array[i]))
                      return false;       
              }           
              else if (this[i] != array[i]) { 
                  // Warning - two different object instances will never be equal: {x:20} != {x:20}
                  return false;   
              }           
          }       
          return true;
      }
      // Hide method from for-in loops
      Object.defineProperty(Array.prototype, "equals", {enumerable: false});
      
      d3.selection.prototype.moveUp = function() {
          return this.each(function() {
              this.parentNode.appendChild(this);
          });
      };
      d3.selection.prototype.first = function() {
        return d3.select(this[0][0]);
      };
      d3.selection.prototype.last = function() {
        var last = this.size() - 1;
        return d3.select(this[0][last]);
      };
      function parsing_to_string(x) {
        if(Object.values(x).length > 0) {
          var result = Number.parseFloat(Object.values(x)[0]).toFixed(2).toString();
          for(var i = 1; i < Object.values(x).length; ++i) {
            result += " "+Number.parseFloat(Object.values(x)[i]).toFixed(2).toString();
          }
          return result;
        } else return "";
      };
      function getRandom(min, max) {
        return (Math.random() * (max - min)) + min;
      };
    </script>
  
    <link rel="stylesheet" type="text/css" href="static/css/bootstrap-reboot.css">
    <link rel="stylesheet" type="text/css" href="static/css/ion.rangeSlider.css">
    <link rel="stylesheet" type="text/css" href="static/css/ion.rangeSlider.skinShiny.css">
    <link rel="stylesheet" type="text/css" href="static/css/simplex2.css">
    <link rel="stylesheet" type="text/css" href="static/css/style.css">
    <style>
      body {
        background-color: white;
        margin: 10px;
        font-family: sans-serif;
        //font-size: 18px;
      }
      .containers {
        //pointer-events: all;
      }
      #zoomObject_PS {
      }
      .interval {
        vector-effect: non-scaling-stroke; 
      }
      .loop {
        vector-effect: non-scaling-stroke; 
      }
      .transition { 
        vector-effect: non-scaling-stroke; 
      }
      .states {
        vector-effect: non-scaling-stroke; 
      }
      .axis {
        font-size: 15px;
      }
      .widget_panel {
      }
      .label {
        font-size: 15px;
      }
      #resetZoomBtn_PS {
      }
      #addMoreSamplePointsBtn_PS {
      }
      #slider_PS_radius_wrapper {
      }
      #resetReachBtn_PS {
      }
      #resetReachOneBtn_PS {
      }
      #checkbox_PS_mode {
      }
      #text_PS_mode {
      }
      #infoPanel_PS {
        flex-grow: 1;
      }
      #x_axis_PS_div {
      }
      #y_axis_PS_div {
      }
      #slidecontainer_PS {
      }
      #formula_div {
      }
      
      #resetZoomBtn_SS {
      }
      #resetReachBtn_SS {
      }
      #infoPanel_SS {
        flex-grow: 1;
      }
      #x_axis_SS_div {
      }
      #y_axis_SS_div {
      }
      #slidecontainer_SS {
      }
    </style>

  </head>
  
  <body>
    <div class="my-row">
        <div class="row row-header">
            <div class="col-sm-2 lab">Show results for</div>
            <div class="col-sm-2">
                <select id="formula" class="form-control" required>
                  % for key, val in enumerate(results.keys()):
                    % if key == 0:
                      <option value="${val}" selected>${val}</option>
                    % else:
                      <option value="${val}">${val}</option>
                    % endif
                  % endfor
                </select>
            </div>
            <div class="col-sm-2 lab">Select parameterisation</div>
            <div class="col-sm-2">
                <select id="param_id" class="form-control" required>
                    <option value="all" selected>all</option>
                  % for key, val in enumerate(params_val):
                    <option value="${key}">${key}</option>
                  % endfor
                </select>
            </div>
        </div>
        <hr>
        <div class="row nohide">
            <div class="col-sm-2">
                <div style="text-align: right;">
                    <div><button class="btn btn-default" id="resetZoomBtn_PS">Unzoom</button></div>
                    <div>
                        <div class="form-group row nohide" id="slider_PS_radius_wrapper" hidden>
                          <div class="col-sm-6">
                            <label class="control-label" for="slider_PS_radius" id="text_PS_radius">Radius</label>
                            <input class="js-range-slider" id="slider_PS_radius" data-min=1 data-max=10 data-from=4 data-step=1 min=1 max=10 value=4 step=1 
              							  data-grid="true" data-grid-num="10" data-grid-snap="false" data-prettify-separator="," data-prettify-enabled="true" data-data-type="number" >
                          </div>
                          <div class="col-sm-6">
                            <button class="btn btn-default" id="addMoreSamplePointsBtn_PS">Add points</button>
              						</div>
                        </div>
                    </div>
                    <div class="row nohide">
                      <div class="col-sm-4">  <button class="btn btn-default" id="resetReachBtn_PS">Deselect</button> </div>
                      <div class="col-sm-4" hidden>  <button class="btn btn-default" id="resetReachOneBtn_PS">Deselect last</button> </div>
                      <div class="col-sm-4">
                        <label class="control-label" for="checkbox_PS_mode" id="text_PS_mode">Include</label>
                        <input type="checkbox" value="mode" class="cb" id="checkbox_PS_mode" checked>
                      </div>
                    </div>
                </div>
                <pre id="infoPanel_PS"></pre>
                <div class="row">
                    <div class="col-sm-6" id="x_axis_PS_div">
                        <label class="control-label" for="x_axis_PS" >Horizontal axis</label>
                        <select name="xAxis" id="x_axis_PS" class="form-control" required>
                          % for val in [k[0] for k in params]+vars:
                            % if val == params[0][0]:
                              <option value="${val}" selected>${val}</option>
                            % else:
                              <option value="${val}">${val}</option>
                            % endif
                          % endfor
                        </select>
                    </div>
                    <div class="col-sm-6" id="y_axis_PS_div">
                        <label class="control-label" for="y_axis_PS" >Vertical axis</label>
                        <select name="yAxis" id="y_axis_PS" class="form-control" required>
                          % for val in [k[0] for k in params]+vars:
                            % if len(params) > 1 and val == params[1][0]:
                              <option value="${val}" selected>${val}</option>
                            % else:
                              <option value="${val}">${val}</option>
                            % endif
                          % endfor
                        </select>
                    </div>
                </div>
                <div id="slidecontainer_PS">
                % for val in params:
                  <% 
                  min_val  = float(val[1])
                  max_val  = float(val[2])
                  step_val = abs(max_val-min_val)*0.001
                  %>
                  % if val[0] == params[0][0] or val[0] == params[1][0]:
                    <!--div class="form-group" id="slider_PS_${val[0]}_wrapper" hidden-->
                    <div class="form-group row nohide" id="slider_PS_${val[0]}_wrapper">
                  % else:
                    <div class="form-group row nohide" id="slider_PS_${val[0]}_wrapper">
                  % endif
                      <div class="col-sm-10">
                        <label class="control-label" for="slider_PS_${val[0]}" id="text_PS_${val[0]}">Value of ${val[0]}</label>
                        <input class="js-range-slider" id="slider_PS_${val[0]}" data-min=${min_val} data-max=${max_val} data-from=${min_val} data-step=${step_val} 
  						            min=${min_val} max=${max_val} value=${min_val} step=${step_val} 
          							  data-grid="true" data-grid-num="10" data-grid-snap="false" data-prettify-separator="," data-prettify-enabled="true" data-data-type="number" >
                      </div>
                      <div class="col-sm-2">
                        <label class="control-label" for="checkbox_PS_${val[0]}">whole</label>
                        <input type="checkbox" value="all" class="cb" id="checkbox_PS_${val[0]}" checked>
                      </div>
                    </div>
                % endfor
                
                % for val in vars:
                  <% 
                  min_val  = min(map(float,thrs[val]))
                  max_val  = max(map(float,thrs[val]))
                  step_val = abs(max_val-min_val)*0.01
                  %>
                  <div class="form-group row nohide" id="slider_PS_${val}_wrapper">
                    <div class="col-sm-10">
                      <label class="control-label" for="slider_PS_${val}" id="text_PS_${val}">Value of ${val}</label>
                      <input class="js-range-slider" id="slider_PS_${val}" data-min=${min_val} data-max=${max_val} data-from=${min_val} data-step=${step_val} 
						            min=${min_val} max=${max_val} value=${min_val} step=${step_val} 
        							  data-grid="true" data-grid-num="10" data-grid-snap="false" data-prettify-separator="," data-prettify-enabled="true" data-data-type="number" >
                    </div>
                    <div class="col-sm-2">
                      <label class="control-label" for="checkbox_PS_${val}">whole</label>
                      <input type="checkbox" value="all" class="cb" id="checkbox_PS_${val}" checked>
                    </div>
                  </div>
                % endfor
                </div>
            </div>
            <div class="col-sm-4 visual" id="plot_ps"></div>
            <div class="col-sm-4 visual" id="plot_ss"></div>
            <div class="col-sm-2">
                <div>
                    <div><button class="btn btn-default" id="resetZoomBtn_SS">Unzoom</button></div>
                    <div><button class="btn btn-default" id="resetReachBtn_SS">Deselect</button></div>
                </div>
                <pre id="infoPanel_SS"></pre>
                <div class="row">
                    <div class="col-sm-6" id="x_axis_SS_div">
                        <label class="control-label" for="x_axis_SS" >Horizontal axis</label>
                        <select name="xAxis" id="x_axis_SS" class="form-control" required>
                          % for val in vars:
                            % if val == vars[0]:
                              <option value="${val}" selected>${val}</option>
                            % else:
                              <option value="${val}">${val}</option>
                            % endif
                          % endfor
                        </select>
                    </div>
                    <div class="col-sm-6" id="y_axis_SS_div">
                        <label class="control-label" for="y_axis_SS" >Vertical axis</label>
                        <select name="yAxis" id="y_axis_SS" class="form-control" required>
                          % for val in vars:
                            % if len(vars) > 1 and val == vars[1]:
                              <option value="${val}" selected>${val}</option>
                            % else:
                              <option value="${val}">${val}</option>
                            % endif
                          % endfor
                        </select>
                    </div>
                </div>
                % if len(vars) > 2 :
                  % for val in vars:
                    <% 
                    min_val  = min(map(float,thrs[val]))
                    max_val  = max(map(float,thrs[val]))
                    step_val = abs(max_val-min_val)*0.01
                    %>
                    % if val == vars[0] or val == vars[1]:
                      <div class="form-group row nohide" id="slider_SS_${val}_wrapper" hidden>
                    % else:
                      <div class="form-group row nohide" id="slider_SS_${val}_wrapper">
                    % endif
                        <div class="col-sm-10">
                          <label class="control-label" for="slider_SS_${val}" id="text_SS_${val}">Value of ${val}</label>
                          <input class="js-range-slider" id="slider_SS_${val}" data-min=${min_val} data-max=${max_val} data-from=${min_val} data-step=${step_val} 
    						            min=${min_val} max=${max_val} value=${min_val} step=${step_val} 
            							  data-grid="true" data-grid-num="10" data-grid-snap="false" data-prettify-separator="," data-prettify-enabled="true" data-data-type="number" >
                        </div>
                        <div class="col-sm-2">
                          <label class="control-label" for="checkbox_SS_${val}">whole</label>
                          % if val == vars[0] or val == vars[1]:
                            <input type="checkbox" value="all" class="cb" id="checkbox_SS_${val}" checked>
                          % else:
                            <input type="checkbox" value="all" class="cb" id="checkbox_SS_${val}" checked>
                          % endif
                        </div>
          						</div>
                  % endfor
                % endif
            </div>
        </div>
    </div>
    
    <script type="text/javascript" charset="utf-8">
   
var width = d3.select("#plot_ps").property("offsetWidth"),
    height = d3.select("#plot_ps").property("offsetWidth"),
    xDimPS = document.getElementById("x_axis_PS").value,
    yDimPS = document.getElementById("y_axis_PS").value,
    xDimPS_id = (window.bio.vars.includes(xDimPS) ? window.bio.vars.findIndex(x => x == xDimPS) : window.bio.params.findIndex(x => x[0] == xDimPS)),
    yDimPS_id = (window.bio.vars.includes(yDimPS) ? window.bio.vars.findIndex(x => x == yDimPS) : window.bio.params.findIndex(x => x[0] == yDimPS)),
    xDimSS = document.getElementById("x_axis_SS").value,
    yDimSS = document.getElementById("y_axis_SS").value,
    xDimSS_id = window.bio.vars.findIndex(x => x == xDimSS),
    yDimSS_id = window.bio.vars.findIndex(x => x == yDimSS),
    
    thrs = window.bio.thrs,
    formula = document.getElementById("formula").value,
    inclusion = true,
    param_bounds = [],
    radius = Number(d3.select("#slider_PS_radius").property("value")),
    var_bounds_PS = []
    var_bounds_SS = [];

// initial parametric bounds are not limited (projection through all parametric dimensions)
window.bio.params.forEach(x => param_bounds.push(null));
// initial bounds of variables are not limited (projection through all dimensions)
window.bio.vars.forEach(x => { var_bounds_PS.push(null); var_bounds_SS.push(null); });

if(window.result.type == "smt") {
  d3.select("#slider_PS_radius_wrapper").attr("hidden",null)
}

// iteratively adds event listener for variable sliders in PS (according to index)
% for key, val in enumerate(vars):
    (function(i,d) {
        d3.select("#slider_PS_"+d).on("input", function() {
            if(! d3.select("#checkbox_PS_"+d).property("checked")) {
                var_bounds_PS[i] = Number(d3.select(this).property("value"));
                result_data_relevance()
                compute_projection()
                draw_PS()
                compute_statedata()
                draw_SS()
                redrawClickedStates()
                resetInfoPanel_PS()
            }
        });
        d3.select('#checkbox_PS_'+d).on("change", function() {
            if(! d3.select(this).property("checked")) {
              var_bounds_PS[i] = Number(d3.select("#slider_PS_"+d).property("value"));
            } else {
              var_bounds_PS[i] = null;
            }
            result_data_relevance()
            compute_projection()
            draw_PS()
            compute_statedata()
            draw_SS()
            redrawClickedStates()
            resetInfoPanel_PS()
        });
    })(${key},"${val}");
% endfor

// iteratively adds event listener for parameter sliders in PS (according to index)
% for key, val in enumerate(params):
    (function(i,d) {
        d3.select("#slider_PS_"+d[0]).on("input", function() {
            if(! d3.select("#checkbox_PS_"+d[0]).property("checked")) {
                param_bounds[i] = Number(d3.select(this).property("value"));
                result_data_relevance()
                compute_projection()
                draw_PS()
                compute_statedata()
                draw_SS()
                redrawClickedStates()
                resetInfoPanel_PS()
            }
        });
        d3.select('#checkbox_PS_'+d[0]).on("change", function() {
            if(! d3.select(this).property("checked")) {
              param_bounds[i] = Number(d3.select("#slider_PS_"+d[0]).property("value"));
            } else {
              param_bounds[i] = null;
            }
            result_data_relevance()
            compute_projection()
            draw_PS()
            compute_statedata()
            draw_SS()
            redrawClickedStates()
            resetInfoPanel_PS()
        });
    })(${key},${val});
% endfor

// iteratively adds event listener for variable sliders in SS (according to index)
% for key, val in enumerate(vars):
    (function(i,d) {
      d3.select("#slider_SS_"+d).on("input", function() {
        if(! d3.select("#checkbox_SS_"+d).property("checked")) {
          var_bounds_SS[i] = Number(d3.select(this).property("value"));
          compute_statedata()
          draw_SS()
          resetInfoPanel_SS()
        }
      });
      d3.select('#checkbox_SS_'+d).on("change", function() {
        if(! d3.select(this).property("checked")) {
          var_bounds_SS[i] = Number(d3.select("#slider_SS_"+d).property("value"));
        } else {
          var_bounds_SS[i] = null;
        }
        compute_statedata()
        draw_SS()
        resetInfoPanel_SS()
      });
    })(${key},"${val}");
% endfor
  
// event listener for change of selected dimension for X axis in PS
d3.select("#x_axis_PS").on("change", function() {
  var other = d3.select("#y_axis_PS").property("value");
  if(this.value == other) {
    d3.select("#y_axis_PS").property('value',xDimPS);
    yDimPS = xDimPS;
  } else {
//    d3.select("#slider_"+xDimPS+"_wrapper").attr("hidden",null);
  }
  xDimPS = this.value;
//  d3.select("#slider_"+this.value+"_wrapper").attr("hidden","hidden");
  if(window.bio.vars.includes(xDimPS))  xDimPS_id = window.bio.vars.findIndex(x => x == xDimPS);
  else                                  xDimPS_id = window.bio.params.findIndex(x => x[0] == xDimPS);
  if(window.bio.vars.includes(yDimPS))  yDimPS_id = window.bio.vars.findIndex(x => x == yDimPS);
  else                                  yDimPS_id = window.bio.params.findIndex(x => x[0] == yDimPS);

  resettedZoom_PS()
  compute_projection()
  draw_PS()
  redrawClickedPoints()
});

// event listener for change of selected dimension for Y axis in PS
d3.select("#y_axis_PS").on("change", function() {
  var other = d3.select("#x_axis_PS").property("value");
  if(this.value == other) {
    d3.select("#x_axis_PS").property('value',yDimPS);
    xDimPS = yDimPS;
  } else {
//    d3.select("#slider_PS_"+yDimPS+"_wrapper").attr("hidden",null);
  }
  yDimPS = this.value;
//  d3.select("#slider_PS_"+this.value+"_wrapper").attr("hidden","hidden");
  if(window.bio.vars.includes(xDimPS))  xDimPS_id = window.bio.vars.findIndex(x => x == xDimPS);
  else                                  xDimPS_id = window.bio.params.findIndex(x => x[0] == xDimPS);
  if(window.bio.vars.includes(yDimPS))  yDimPS_id = window.bio.vars.findIndex(x => x == yDimPS);
  else                                  yDimPS_id = window.bio.params.findIndex(x => x[0] == yDimPS);

  resettedZoom_PS()
  compute_projection()
  draw_PS()
  redrawClickedPoints()
});

// event listener for change of selected dimension for X axis in SS
d3.select("#x_axis_SS").on("change", function() {
  var other = d3.select("#y_axis_SS").property("value");
  if(this.value == other) {
    d3.select("#y_axis_SS").property('value',xDimSS);
    yDimSS = xDimSS;
  } else {
    d3.select("#slider_SS_"+xDimSS+"_wrapper").attr("hidden",null);
  }
  xDimSS = this.value;
  d3.select("#slider_SS_"+this.value+"_wrapper").attr("hidden","hidden");
  
  xDimSS_id = window.bio.vars.findIndex(x => x == xDimSS)
  yDimSS_id = window.bio.vars.findIndex(x => x == yDimSS)

  resettedZoom_SS()
  compute_statedata()
  draw_SS()
});
// event listener for change of selected dimension for Y axis in SS
d3.select("#y_axis_SS").on("change", function() {
  var other = d3.select("#x_axis_SS").property("value");
  if(this.value == other) {
    d3.select("#x_axis_SS").property('value',yDimSS);
    xDimSS = yDimSS;
  } else {
    d3.select("#slider_SS_"+yDimSS+"_wrapper").attr("hidden",null);
  }
  yDimSS = this.value;
  d3.select("#slider_SS_"+this.value+"_wrapper").attr("hidden","hidden");

  xDimSS_id = window.bio.vars.findIndex(x => x == xDimSS)
  yDimSS_id = window.bio.vars.findIndex(x => x == yDimSS)

  resettedZoom_SS()
  compute_statedata()
  draw_SS()
});

// event listener for width change of plots (they should be of same size)
d3.select(window).on("resize", function() {
  var newWidth = d3.select("#plot_ps").property("offsetWidth")
  if(newWidth != width) {
    width = newWidth
    height = newWidth
    d3.selectAll("svg").remove()
    
    //TODO: add right methods to invoke recalculation of plots (maybe just check)
    initiate()
    result_data_relevance()
    compute_projection()
    draw_PS()
    
    compute_statedata()
    draw_SS()
  }
})

d3.select("#formula").on("change", function() {
  formula = d3.select("#formula").property("value");
    
  result_data_relevance()
  compute_projection()
  draw_PS()
  compute_statedata()
  draw_SS()
});

d3.select("#param_id").on("change", function() {
  
  compute_projection()
  draw_PS()
})

d3.select('#checkbox_PS_mode').on("change", function() {
    if(d3.select("#checkbox_PS_mode").property("checked")) {
        d3.select("#text_PS_mode").html("include")
        inclusion = true
    } else {
        d3.select("#text_PS_mode").html("exclude")
        inclusion = false
    }
})

d3.select('#addMoreSamplePointsBtn_PS')
    .on("click", addMoreSamplePointsClick_PS)
d3.select('#slider_PS_radius')
    .on("change", function() {
      radius = d3.select("#slider_PS_radius").property("value")
      zoomed_PS()
    })

d3.select('#resetReachOneBtn_PS')
    .on("click", reverseLastClick_PS)
d3.select('#resetReachBtn_PS')
    .on("click", resettedClick_PS)
d3.select('#resetReachBtn_SS')
    .on("click", resettedClick_SS)

d3.select('#resetZoomBtn_PS')
    .on("click", resettedZoom_PS)
d3.select('#resetZoomBtn_SS')
    .on("click", resettedZoom_SS)
    
//###################################################    

var margin = { top: 15, right: 15, bottom: 50, left: 50 },
    edgelen = 7,
    bgColor = d3.select("body").style("background-color"),
    noColor = "transparent",
    reachColor = "rgb(65, 105, 225)", // "royalblue"
    unselectedColor = "rgba(65, 105, 225, 0.5)", // "royalblue" with lower opacity
    neutral_col = "black",
    positive_col = "darkgreen",
    negative_col = "red",
    normalStrokeWidth = 1,
    hoverStrokeWidth = 4,
    markerWidth = 2,
    projdata = [],
    statedata = [],
    selectedStates = [],
    selectedParams = [],
    clicked_states_PS = [],
    clicked_points_PS = [],
    zoomObject_PS = d3.zoomIdentity,
    zoomObject_SS = d3.zoomIdentity
    
var infoPanel_SS_lines = [
  "State id(s): none",
  "Sat. states #: none",
  % for id,v in enumerate(vars):
    '${v}: '+('${v}' == xDimSS || '${v}' == yDimSS || d3.select("#checkbox_SS_${v}").property("checked") ? 
                        '['+(${min([float(i) for i in thrs[v]])}).toFixed(3)+', '+(${max([float(i) for i in thrs[v]])}).toFixed(3)+']' : 
                        '['+(d3.max(${[float(i) for i in thrs[v]]}.filter(k => k <= Number(d3.select("#slider_SS_${v}").property("value"))))).toFixed(3)+', '
                           +(d3.min(${[float(i) for i in thrs[v]]}.filter(k => k > Number(d3.select("#slider_SS_${v}").property("value"))))).toFixed(3)+']'),
  % endfor
],
    infoPanel_PS_lines = [
  "States cov: unknown",
  "Param. cov: unknown",
  % for id,v in enumerate(params):
    '${v[0]}: '+('${v[0]}' == xDimPS || '${v[0]}' == yDimPS || d3.select("#checkbox_PS_${v[0]}").property("checked") ? 
                          '['+(${v[1]}).toFixed(3)+', '+(${v[2]}).toFixed(3)+']' : 
                          Number(d3.select("#slider_PS_${v[0]}").property("value")).toFixed(3)),
  % endfor
  % for id,v in enumerate(vars):
    '${v}: '+('${v}' == xDimPS || '${v}' == yDimPS || d3.select("#checkbox_PS_${v}").property("checked") ? 
              '['+(${min([float(i) for i in thrs[v]])}).toFixed(3)+', '+(${max([float(i) for i in thrs[v]])}).toFixed(3)+']' : 
              Number(d3.select("#slider_PS_${v}").property("value")).toFixed(3)),
  % endfor
]


function initiate() {
  // Definitions of D3 scales used in visualisation
  xScalePS = d3.scaleLinear()
        .domain([d3.min(thrs[xDimPS],parseFloat),
                 d3.max(thrs[xDimPS],parseFloat)])
        .range([margin.left, width - margin.right])
  xScaleSS = d3.scaleLinear()
        .domain([d3.min(thrs[xDimSS],parseFloat),
                 d3.max(thrs[xDimSS],parseFloat)])
        .range([margin.left, width - margin.right])
  
  yScalePS = d3.scaleLinear()
        .domain([d3.min(thrs[yDimPS],parseFloat),
                 d3.max(thrs[yDimPS],parseFloat)])
        .range([height - margin.bottom, margin.top])
  yScaleSS = d3.scaleLinear()
        .domain([d3.min(thrs[yDimSS],parseFloat),
                 d3.max(thrs[yDimSS],parseFloat)])
        .range([height - margin.bottom, margin.top])
  
  // Definitions of D3 brush objects for plots in visualisation (each plot can be brushed in both axis separately)      
  brushXPS = d3.brushX()
      .extent([[margin.left, 0], [width-margin.right, margin.bottom]])
      .on("end", brushedX_PS)
      
  brushYPS = d3.brushY()
      .extent([[-margin.left, margin.top], [0, height-margin.bottom]])
      .on("end", brushedY_PS)
      
  brushXSS = d3.brushX()
      .extent([[margin.left, 0], [width-margin.right, margin.bottom]])
      .on("end", brushedX_SS)
      
  brushYSS = d3.brushY()
      .extent([[-margin.left, margin.top], [0, height-margin.bottom]])
      .on("end", brushedY_SS)
  
  // Definitions of D3 zoom objects for plots in vis
  // TODO: boundaries are moving when zooming in
  zoomPS = d3.zoom()
            .scaleExtent([1, Infinity])
            .translateExtent([[0,0],[width,height]])
            .on("zoom", zoomed_PS)
  zoomSS = d3.zoom()
            .scaleExtent([1, Infinity])
            .translateExtent([[0,0],[width,height]])
            .on("zoom", zoomed_SS)
            
  svgPS = d3.select("#plot_ps").append("svg")
        .attr("width", width)
        .attr("height", height)
  svgSS = d3.select("#plot_ss").append("svg")
        .attr("width", width)
        .attr("height", height)
  
  containerPS = svgPS.append("g")
          .attr("class", "containers")
          .attr("id","cont_ps")
          .attr("pointer-events", "all")
          //.attr("transform", "translate("+(margin.left)+","+(margin.top)+")")
          .call(zoomPS)
  containerSS = svgSS.append("g")
          .attr("class", "containers")
          .attr("id","cont_ss")
          .attr("pointer-events", "all")
          //.attr("transform", "translate("+(margin.left)+","+(margin.top)+")")
          .call(zoomSS)
          
  // important box to cover svg content outside the axis-bounded window while zooming or moving 
  svgPS.append("rect")
      .attr("x", 0)
      .attr("y", height-margin.bottom)
      .attr("width", width)
      .attr("height", margin.bottom)
      .attr("fill", bgColor)
  svgPS.append("rect")
      .attr("x", 0)
      .attr("y", 0)
      .attr("width", margin.left)
      .attr("height", height)
      .attr("fill", bgColor)
  svgPS.append("rect")
      .attr("x", 0)
      .attr("y", 0)
      .attr("width", width)
      .attr("height", margin.top)
      .attr("fill", bgColor)
  svgPS.append("rect")
      .attr("x", width-margin.right)
      .attr("y", 0)
      .attr("width", margin.right)
      .attr("height", height)
      .attr("fill", bgColor)
  svgSS.append("rect")
      .attr("x", 0)
      .attr("y", height-margin.bottom)
      .attr("width", width)
      .attr("height", margin.bottom)
      .attr("fill", bgColor)
  svgSS.append("rect")
      .attr("x", 0)
      .attr("y", 0)
      .attr("width", margin.left)
      .attr("height", height)
      .attr("fill", bgColor)
  svgSS.append("rect")
      .attr("x", 0)
      .attr("y", 0)
      .attr("width", width)
      .attr("height", margin.top)
      .attr("fill", bgColor)
  svgSS.append("rect")
      .attr("x", width-margin.right)
      .attr("y", 0)
      .attr("width", margin.right)
      .attr("height", height)
      .attr("fill", bgColor)
  
  xLabelPS = svgPS.append("text")
        .attr("id", "xLabelPS")
        .attr("class", "label")
        .attr("x", width*0.5)
        .attr("y", height-10)
        .attr("stroke", "black")
        .text(function() { return xDimPS; })
  xLabelSS = svgSS.append("text")
        .attr("id", "xlabelSS")
        .attr("class", "label")
        .attr("x", width*0.5)
        .attr("y", height-10)
        .attr("stroke", "black")
        .text(function() { return xDimSS; })
  yLabelPS = svgPS.append("text")
        .attr("id", "yLabelPS")
        .attr("class", "label")
        .attr("transform", "rotate(-90)")
        .attr("x", -height*0.5)
        .attr("y", 15)
        .attr("stroke", "black")
        .text(function() { return yDimPS; })
  yLabelSS = svgSS.append("text")
        .attr("id", "yLabelSS")
        .attr("class", "label")
        .attr("transform", "rotate(-90)")
        .attr("x", -height*0.5)
        .attr("y", 15)
        .attr("stroke", "black")
        .text(function() { return yDimSS; })
  
  defs = svgPS.append("svg:defs")
  defs.append("svg:marker")
  		.attr("id", "greenCross")
  		.attr("viewBox", "0 0 "+edgelen+" "+edgelen)
  		.attr("refX", 0.5*edgelen)
  		.attr("refY", 0.5*edgelen)
  		.attr("markerWidth", edgelen)
  		.attr("markerHeight", edgelen)
  		.attr("orient","auto")
      .append("svg:path")
        .attr("stroke", positive_col)
        //.attr("stroke-width", markerWidth)
  			.attr("d", "M0,"+(0)+" L"+edgelen+","+edgelen+" M0,"+edgelen+" L"+edgelen+",0")
  			.attr("class","clickMark")
  defs.append("svg:marker")
  		.attr("id", "redCross")
  		.attr("viewBox", "0 0 "+edgelen+" "+edgelen)
  		.attr("refX", 0.5*edgelen)
  		.attr("refY", 0.5*edgelen)
  		.attr("markerWidth", edgelen)
  		.attr("markerHeight", edgelen)
  		.attr("orient","auto")
      .append("svg:path")
        .attr("stroke", negative_col)
        //.attr("stroke-width", markerWidth)
  			.attr("d", "M0,"+(0)+" L"+edgelen+","+edgelen+" M0,"+edgelen+" L"+edgelen+",0")
  			.attr("class","arrowHead")
  
  bottomPanelPS = svgPS.append("g")
      .attr("id", "bPanelPS")
      .attr("class", "panel")
      .attr("transform", "translate("+(0)+","+(height-margin.bottom)+")")
  xAxisPS = d3.axisBottom(xScalePS)
      .tickFormat(
        d3.format(
          Math.abs(xScalePS.domain()[0]) <  0.01 ||
          Math.abs(xScalePS.domain()[0]) >= 1000 ||
          Math.abs(xScalePS.domain()[1]) <  0.01 ||
          Math.abs(xScalePS.domain()[1]) >= 1000 ?
          ".2~e" : ".3~r"));
  gXPS = bottomPanelPS.append("g")
      .attr("id", "xAxisPS")
      .attr("class", "axis")
      .call(xAxisPS); // Create an axis component with d3.axisBottom
  gBXPS = bottomPanelPS.append("g")
      .attr("id", "xBrushPS")
      .attr("class", "brush")
      .call(brushXPS);
      
  leftPanelPS = svgPS.append("g")
      .attr("id", "lPanelPS")
      .attr("class", "panel")
      .attr("transform", "translate("+(margin.left)+","+(0)+")")
  yAxisPS = d3.axisLeft(yScalePS)
      .tickFormat(
        d3.format(
          Math.abs(yScalePS.domain()[0]) <  0.01 ||
          Math.abs(yScalePS.domain()[0]) >= 1000 ||
          Math.abs(yScalePS.domain()[1]) <  0.01 ||
          Math.abs(yScalePS.domain()[1]) >= 1000 ?
          ".2~e" : ".3~r"));
  gYPS = leftPanelPS.append("g")
      .attr("id", "yAxisPS")
      .attr("class", "axis")
      .call(yAxisPS); // Create an axis component with d3.axisLeft
  gBYPS = leftPanelPS.append("g")
      .attr("id", "xBrushPS")
      .attr("class", "brush")
      .call(brushYPS);
  
  bottomPanelSS = svgSS.append("g")
      .attr("id", "bPanelSS")
      .attr("class", "panel")
      .attr("transform", "translate("+(0)+","+(height-margin.bottom)+")")
  xAxisSS = d3.axisBottom(xScaleSS)
      .tickFormat(
        d3.format(
          Math.abs(xScaleSS.domain()[0]) <  0.01 ||
          Math.abs(xScaleSS.domain()[0]) >= 1000 ||
          Math.abs(xScaleSS.domain()[1]) <  0.01 ||
          Math.abs(xScaleSS.domain()[1]) >= 1000 ?
          ".2~e" : ".3~r"));
  gXSS = bottomPanelSS.append("g")
      .attr("id", "xAxisSS")
      .attr("class", "axis")
      .call(xAxisSS); // Create an axis component with d3.axisBottom
  gBXSS = bottomPanelSS.append("g")
      .attr("id", "xBrushSS")
      .attr("class", "brush")
      .call(brushXSS);
      
  leftPanelSS = svgSS.append("g")
      .attr("id", "lPanelSS")
      .attr("class", "panel")
      .attr("transform", "translate("+(margin.left)+","+(0)+")")
  yAxisSS = d3.axisLeft(yScaleSS)
      .tickFormat(
        d3.format(
          Math.abs(yScaleSS.domain()[0]) <  0.01 ||
          Math.abs(yScaleSS.domain()[0]) >= 1000 ||
          Math.abs(yScaleSS.domain()[1]) <  0.01 ||
          Math.abs(yScaleSS.domain()[1]) >= 1000 ?
          ".2~e" : ".3~r"));
  gYSS = leftPanelSS.append("g")
      .attr("id", "yAxisSS")
      .attr("class", "axis")
      .call(yAxisSS); // Create an axis component with d3.axisLeft
  gBYSS = leftPanelSS.append("g")
      .attr("id", "xBrushSS")
      .attr("class", "brush")
      .call(brushYSS);
      
  d3.select("#infoPanel_PS").property("innerHTML", infoPanel_PS_lines.join("\n"))
  d3.select("#infoPanel_SS").property("innerHTML", infoPanel_SS_lines.join("\n"))
}

initiate()
result_data_relevance()
compute_projection()
draw_PS()

compute_statedata()
draw_SS()

// ################# definitions of functions #################

function result_data_relevance() {
  all_pairs = window.result.map[formula];
  
  var valid_pairs = []
  for(var r=0, len=all_pairs.length; r<len; ++r) {
    var sid = Number(all_pairs[r][0])
    var pid = Number(all_pairs[r][1])
    var param_set = window.result.params[pid]
    
    var shown = true
    var vid = 0
    while(shown && vid < var_bounds_PS.length) {
      const bound = var_bounds_PS[vid]
      if(bound !== null && (d3.min(window.result.states[sid][vid]) > bound || d3.max(window.result.states[sid][vid]) < bound)) shown = false
      vid++
    }
    if(shown) {
      if(window.result.type != "smt") {
        for(var i=0, len2=param_set.length; i<len2; ++i) {
          var interval = param_set[i];
          var par_id = 0;
          while(shown && par_id < param_bounds.length) {
            const bound = param_bounds[par_id]
            if(bound !== null && (d3.min(interval[par_id]) > bound || d3.max(interval[par_id]) < bound)) shown = false
            par_id++
          }
          if(shown) valid_pairs.push([sid,pid])
        }
      } else valid_pairs.push([sid,pid])
    }
  }
  map_PS = {}
  map_SS = {}
  for(var i=0, len=valid_pairs.length; i<len; ++i) {
    const sid = Number(valid_pairs[i][0])
    const pid = Number(valid_pairs[i][1])
    map_PS[sid] = pid
    if(map_SS[pid] === undefined) map_SS[pid] = [sid]
    else map_SS[pid].push(sid)
  }
  if(window.result.type == 'smt') {
    // symbolic parameters based on SMT formulae
    // TODO: reduce following part so context_map might not be needed
    context_map = {}   // dict for each model parameter it contains either one particular value or a list of random values within its bounds (as defined in the model)
    for(var p=0; p < window.bio.params.length; p++) {
      // if the boundary is set it will be passed to context_map
      var context = [param_bounds[p]]
      if(param_bounds[p] === null) {
        // if the boundary is NOT set a particular context will be generated
        var nPoints = 200
        context = new Array(nPoints)
        low  = window.bio.params[p][1]
        high = window.bio.params[p][2]
        for(var i=0, len=nPoints; i<len; i++) {
          context[i] = getRandom(low,high)
        }
      }
      context_map[window.bio.params[p][0]] = context
    }
    context_map['length'] = d3.max(Object.values(context_map).map(d => d.length))
    ////////////////
    map_CTX = {}
    for(var i=0, len2=context_map["length"]; i<len2; ++i) {
      var valid_formulae = new Set()
      var valid_states   = new Set()
      var context = {}
      for(var j=0; j<window.bio.params.length; ++j) {
        var pname = window.bio.params[j][0]
        var value = context_map[pname].length > 1 ? context_map[pname][i] : context_map[pname][0] // coordinate of parametrization point
        context[pname] = value
      }
      context['TRUE'] = true
      context['FALSE'] = false

      for(var p=0, len=Object.values(map_PS).length; p<len; ++p) {
        const sid = Object.keys(map_PS)[p]
        const pid = Object.values(map_PS)[p]
        const formula = window.result.params[pid]
        if(valid_formulae.has(pid)) {
          valid_states.add(sid)
        } else {
          if(math.eval(formula, context)) {
            valid_formulae.add(pid)
            valid_states.add(sid)
          }
        }
      }
      map_CTX[i] = { 'ctx': context, 'state_ids': valid_states, 'param_ids': valid_formulae }
    }
  }
  console.log("# of states is "+(Object.keys(map_PS).length))
  console.log("# of unique formulae is "+(new Set(Object.values(map_PS)).size))
}
    
function compute_projection() {
  projdata = [];
  var state_ids = [],
      param_ids = [];

  if (Object.values(map_PS).length > 0) {
    state_ids = Object.keys(map_PS)
    param_ids = Object.values(map_PS)
      
    if(window.result.type == 'smt') {
      for(var i=0, len2=Object.keys(map_CTX).length; i<len2; ++i) {
        var ctx = Object.assign({}, map_CTX[i]['ctx'])
        
        if(window.bio.vars.includes(xDimPS) || window.bio.vars.includes(yDimPS)) {
          // combination plot of parameter and variable - we need to draw lines as an extension of point with valid states width
          var name = window.bio.vars.includes(xDimPS) ? xDimPS : yDimPS
          var vid  = window.bio.vars.includes(xDimPS) ? xDimPS_id : yDimPS_id
          var states = {}
          states[name] = []
          states['scov'] = []
          Array.from(map_CTX[i]['state_ids']).reduce((obj,sid) => {
            var bound = window.result.states[sid][vid]
            var uniq = true
            for(var j=0,len3=obj[name].length; j<len3; ++j) {
              if(obj[name][j].equals(bound)) {
                uniq = false
                obj['scov'][j]++
                break
              }
            }
            if(uniq) {
              obj[name].push(bound)
              obj['scov'].push(1)
            }
            return obj 
          }, states)
          for(var j=0,len3=states[name].length; j<len3; ++j) {
            var data = Object.assign({}, ctx)
            data[name] = states[name][j]
            projdata.push({
              "data": [data],
              "id"  : i+"x"+j,
              "cov" : states['scov'][j],
              "pcov": map_CTX[i]['param_ids'].size
            })
          }
        } else {
          // just parameter space - so only points coordinates are needed
          if(map_CTX[i]['param_ids'].size > 0) {
            projdata.push({
              "data": [ctx],
              "id"  : i,
              "cov" : map_CTX[i]['state_ids'].size,
              "pcov": map_CTX[i]['param_ids'].size
            })
          } 
        }
      }
    } else {
      // TODO: check funcionality of following code (probably not working for dep params)
      if(d3.select("#param_id").property("value") == "all") {
        for(var p=0, len=param_ids.length; p<len; ++p) {
          const sid = state_ids[p]
          const param_id = param_ids[p]
          const param_set = window.result.params[param_id]
          var data = []
          
          for(var i=0, len2=param_set.length; i<len2; ++i) {
            var interval = param_set[i]
            // reduces array of arrays for param interval bounds into object of arrays indicated with parameter name (starting with empty object) and then
            // reduces array of arrays for state rectangle bounds into object of arrays indicated with variable name (starting with previous object to concat both together)
            var all_data = {}
            window.result.states[sid].reduce((obj,d,i) => { obj[window.bio.vars[i]] = d; return obj }, all_data)
            interval.reduce((obj,d,i) => { obj[window.bio.params[i][0]] = d; return obj }, all_data)
            
            data.push({
              x:    all_data[xDimPS], //(window.bio.vars.includes(xDimPS) ? window.result.states[sid][xDimPS_id] : interval[xDimPS_id]),
              y:    all_data[yDimPS], //(window.bio.vars.includes(yDimPS) ? window.result.states[sid][yDimPS_id] : interval[yDimPS_id]),
              all:  all_data
            })
          }
          if(data.length > 0) {
            projdata.push({
              "data": data,
              "id": sid+"x"+param_id,
              "cov": 1  // TODO: obsolute, should be removed probably
            })
          }
        }
      } else {
        const p = d3.select("#param_id").property("value");
        const param_set = window.result.params[p];
    
        var data = [];
        for(var i=0, len2=param_set.length; i<len2; ++i) {
          var interval = param_set[i];
          data.push({
            x: interval[xDimPS_id],
            y: interval[yDimPS_id],
          })
        }
        if(data.length > 0) {
          projdata.push({
            "data": data,
            "id"  : p,
            "cov" : Object.values(map_PS).filter( x => x == p ).length
          })
        }
      }
    }
  }
}
function compute_statedata() {
  statedata = []
  const vars = window.bio.vars.filter(x => x != xDimSS && x != yDimSS)
  var state_ids = []
  for(var s=0, len=Object.keys(map_SS).length; s<len; ++s) 
    Object.values(map_SS)[s].forEach(x => state_ids.push(x))
  
  var data = {}
  for(var i=0, len=Object.values(window.result.states).length; i < len; ++i) {
    var id    = Number(Object.entries(window.result.states)[i][0])
    var state = Object.entries(window.result.states)[i][1]
    var flat_id = window.bio.thrs[xDimSS].indexOf(state[xDimSS_id][0])+"x"+window.bio.thrs[yDimSS].indexOf(state[yDimSS_id][0])
    
    var shown = true
    var v = 0
    while(shown && v < vars.length) {
      const vid = window.bio.vars.indexOf(vars[v])  // 'v' should be equal to 'vid' (just for case of some uncaught reorganization)
      const thr = var_bounds_SS[vid]
      if(thr !== null && (state[vid][0] > thr || state[vid][1] < thr)) shown = false
      v++
    }
    
    if(shown) {
      if(data[flat_id] === undefined) {
        data[flat_id] = {
          "x" : state[xDimSS_id][0],
          "y" : state[yDimSS_id][1],
          "x1": state[xDimSS_id][1],
          "y1": state[yDimSS_id][0],
          "ids":[id]
        }
      } else data[flat_id]["ids"].push(id)
    }
  }
  var opac = 0.2
  for(var i=0,len=Object.values(data).length; i<len; ++i) {
    const dt = Object.entries(data)[i][1]
    const positive = dt["ids"].filter(id => state_ids.includes(id)) //subset of states where at least one parameterisation satisfies the property (satisfying states)
    const selected = positive.filter(id  => selectedStates.includes(id))  //subset of satisfying states selected with mouse-click (only satisfying states should be selectable)
    const relevant = positive.filter(id  => clicked_states_PS.includes(""+id)) //subset of satisfying states where selected parameterisations are satisfied
    statedata.push({
      "x" : dt["x"],
      "y" : dt["y"],
      "x1": dt["x1"],
      "y1": dt["y1"],
      "id": dt["ids"],
      "strokeWidth": (relevant.length > 0 ? hoverStrokeWidth : normalStrokeWidth),
      "positive": positive,
      //"opac": (dt["ids"].length == 1 || selected.length > 0 ? 1 : positive.length*opac),
      "color": (positive.length > 0 ? (selected.length > 0 ? positive_col : reachColor) : noColor)
    })
  }
}
//######### SS part for zooming ############
function update_axes_SS() {
  // Update axes labels according to selected dimensions
  d3.select('#xLabelSS').text(xDimSS);
  d3.select('#yLabelSS').text(yDimSS);
  // Update scales according to selected diemnsions
  xScaleSS.domain([d3.min(thrs[xDimSS],parseFloat),
                   d3.max(thrs[xDimSS],parseFloat)])

  yScaleSS.domain([d3.min(thrs[yDimSS],parseFloat),
                   d3.max(thrs[yDimSS],parseFloat)])
  // Update an axis component according to selected dimensions
  xAxisSS = d3.axisBottom(xScaleSS);
  gXSS.call(xAxisSS);
  yAxisSS = d3.axisLeft(yScaleSS);
  gYSS.call(yAxisSS);
  // reset brushes
  gBXSS.call(brushXSS.move, null);
  gBYSS.call(brushYSS.move, null);
}
function resettedZoom_SS() {
  update_axes_SS()
  containerSS.transition()
      .duration(500)
      .call(zoomSS.transform, d3.zoomIdentity);
}
function zoomed_SS() {
  if(d3.event.transform) zoomObject_SS = d3.event.transform;
  x = zoomObject_SS.rescaleX(xScaleSS);
  y = zoomObject_SS.rescaleY(yScaleSS);
  
  d3.selectAll(".states")
    .attr("x", d => x(d.x))
    .attr("y", d => y(d.y))
    .attr("width", d => x(d.x1)-x(d.x))
    .attr("height", d => y(d.y1)-y(d.y))
  
  gXSS.call(xAxisSS.scale(x));
  gYSS.call(yAxisSS.scale(y));
  // reset brushes
  gBXSS.call(brushXSS.move, null);
  gBYSS.call(brushYSS.move, null);
  
  resetInfoPanel_SS()
}
function resetInfoPanel_SS() {
  var off = 2
  for(var v = 0; v < window.bio.vars.length; v++) {
    var key = window.bio.vars[v]
    if(key == xDimSS)
      infoPanel_SS_lines[v+off] = [key,": [",zoomObject_SS.rescaleX(xScaleSS).domain()[0].toFixed(3),
                                   ", ",zoomObject_SS.rescaleX(xScaleSS).domain()[1].toFixed(3),"]"].join("")
    else if(key == yDimSS)
      infoPanel_SS_lines[v+off] = [key,": [",zoomObject_SS.rescaleY(yScaleSS).domain()[0].toFixed(3),
                                   ", ",zoomObject_SS.rescaleY(yScaleSS).domain()[1].toFixed(3),"]"].join("")
    else if(var_bounds_SS[v] !== null)
      infoPanel_SS_lines[v+off] = [key,": [",Number(d3.max(thrs[key].filter(x => x <= var_bounds_SS[v]))).toFixed(3),
                                    ", ",Number(d3.min(thrs[key].filter(x => x > var_bounds_SS[v]))).toFixed(3),"]"].join("")
    else
      infoPanel_SS_lines[v+off] = [key,": [",Number(d3.min(thrs[key])).toFixed(3),
                                    ", ",Number(d3.max(thrs[key])).toFixed(3),"]"].join("")
  }
  d3.select("#infoPanel_SS").property("innerHTML", infoPanel_SS_lines.join("\n"))
}
function brushedX_SS() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(xAxisSS.scale().invert);
  
  scale = xScaleSS.copy().domain(domain);
  range = scale.range().map(x => zoomObject_SS.applyX(x));
  domain = range.map(scale.invert);
  xScaleSS.domain(domain);
  
  zoomed_SS();
}
function brushedY_SS() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(yAxisSS.scale().invert);
  
  scale = yScaleSS.copy().domain(domain.reverse());
  range = scale.range().map(y => zoomObject_SS.applyY(y));
  domain = range.map(scale.invert);
  yScaleSS.domain(domain);
  
  zoomed_SS();
}

//######### PS part for zooming ############
function update_axes_PS() {
  // Update axes labels according to selected diemnsions
  d3.select('#xLabelPS').text(xDimPS);
  d3.select('#yLabelPS').text(yDimPS);
  // Update scales according to selected diemnsions
  xScalePS.domain([d3.min(thrs[xDimPS],parseFloat),
                   d3.max(thrs[xDimPS],parseFloat)])

  yScalePS.domain([d3.min(thrs[yDimPS],parseFloat),
                   d3.max(thrs[yDimPS],parseFloat)])
  // Update an axis component according to selected dimensions
  xAxisPS = d3.axisBottom(xScalePS);
  gXPS.call(xAxisPS);
  yAxisPS = d3.axisLeft(yScalePS);
  gYPS.call(yAxisPS);
  // reset brushes
  gBXPS.call(brushXPS.move, null);
  gBYPS.call(brushYPS.move, null);
}
function resettedZoom_PS() {
  update_axes_PS()
  containerPS.transition()
      .duration(500)
      .call(zoomPS.transform, d3.zoomIdentity);
}
function zoomed_PS() {
  if(d3.event.transform) zoomObject_PS = d3.event.transform;
  x = zoomObject_PS.rescaleX(xScalePS);
  y = zoomObject_PS.rescaleY(yScalePS);
  
  d3.selectAll(".interval")
  .attr("d", d => {
    var path = "";
    for(var i=0, len=d.data.length; i<len; ++i) {
      //var r = d.data[i];
      //path += " M"+x(r.x[0])+" "+y(r.y[0])+" H"+x(r.x[1])+" V"+y(r.y[1])+" H"+x(r.x[0])+" z"
      var r = d.data[i];
      // Y scale is inverted, therefore, we use the the higher threshold as the first one and the lower threshold as the second one
      if(window.result.type != 'smt')
        path += " M"+x(r.x[0])+","+y(r.y[1])+" H"+x(r.x[1])+" V"+y(r.y[0])+" H"+x(r.x[0])
      else {
          if(window.bio.vars.includes(xDimPS) || window.bio.vars.includes(yDimPS)) {
            if(window.bio.vars.includes(xDimPS)) {
              path += " M"+zoomObject_PS.rescaleX(xScalePS)(r[xDimPS][0])+","+(zoomObject_PS.rescaleY(yScalePS)(r[yDimPS])+radius)+" H"+zoomObject_PS.rescaleX(xScalePS)(r[xDimPS][1])+" V"+(zoomObject_PS.rescaleY(yScalePS)(r[yDimPS])-radius)+" H"+zoomObject_PS.rescaleX(xScalePS)(r[xDimPS][0])
            } else {
              path += " M"+(zoomObject_PS.rescaleX(xScalePS)(r[xDimPS])+radius)+","+zoomObject_PS.rescaleY(yScalePS)(r[yDimPS][0])+" V"+zoomObject_PS.rescaleY(yScalePS)(r[yDimPS][1])+" H"+(zoomObject_PS.rescaleX(xScalePS)(r[xDimPS])-radius)+" V"+zoomObject_PS.rescaleY(yScalePS)(r[yDimPS][0])
            }
          } else
            path += " M"+zoomObject_PS.rescaleX(xScalePS)(r[xDimPS])+","+zoomObject_PS.rescaleY(yScalePS)(r[yDimPS])+" m -"+radius+",0 a"+radius+","+radius+" 0 1,0 "+(2*radius)+",0 a"+radius+","+radius+" 0 1,0 -"+(2*radius)+",0"
      }
    };
    return path;
  })
  redrawClickedPoints()
  
  gXPS.call(xAxisPS.scale(x));
  gYPS.call(yAxisPS.scale(y));
  // reset brushes
  gBXPS.call(brushXPS.move, null);
  gBYPS.call(brushYPS.move, null);
    
  resetInfoPanel_PS()
}
function resetInfoPanel_PS() {
  var off = 2
  for(var v = 0; v < window.bio.params.length; v++) {
    var key = window.bio.params[v][0]
    if(key == xDimPS)
      infoPanel_PS_lines[v+off] = [key,": [",zoomObject_PS.rescaleX(xScalePS).domain()[0].toFixed(3),
                                    ", ",zoomObject_PS.rescaleX(xScalePS).domain()[1].toFixed(3),"]"].join("")
    else if(key == yDimPS)
      infoPanel_PS_lines[v+off] = [key,": [",zoomObject_PS.rescaleY(yScalePS).domain()[0].toFixed(3),
                                    ", ",zoomObject_PS.rescaleY(yScalePS).domain()[1].toFixed(3),"]"].join("")
    else 
      infoPanel_PS_lines[v+off] = [key,": [",Number(window.bio.params[v][1]).toFixed(3),
                                    ", ",Number(window.bio.params[v][2]).toFixed(3),"]"].join("")
    if(param_bounds[v] !== null)
      infoPanel_PS_lines[v+off] += [" (",Number(param_bounds[v]).toFixed(3),")"].join("")
  }
  off += window.bio.params.length
  for(var v = 0; v < window.bio.vars.length; v++) {
    var key = window.bio.vars[v]
    if(key == xDimPS)
      infoPanel_PS_lines[v+off] = [key,": [",zoomObject_PS.rescaleX(xScalePS).domain()[0].toFixed(3),
                                    ", ",zoomObject_PS.rescaleX(xScalePS).domain()[1].toFixed(3),"]"].join("")
    else if(key == yDimPS)
      infoPanel_PS_lines[v+off] = [key,": [",zoomObject_PS.rescaleY(yScalePS).domain()[0].toFixed(3),
                                    ", ",zoomObject_PS.rescaleY(yScalePS).domain()[1].toFixed(3),"]"].join("")
    else 
      infoPanel_PS_lines[v+off] = [key,": [",Number(d3.min(thrs[key])).toFixed(3),
                                    ", ",Number(d3.max(thrs[key])).toFixed(3),"]"].join("")
    if(var_bounds_PS[v] !== null)
      infoPanel_PS_lines[v+off] += [" (",Number(var_bounds_PS[v]).toFixed(3),")"].join("")
  }
  d3.select("#infoPanel_PS").property("innerHTML", infoPanel_PS_lines.join("\n"))
}
function brushedX_PS() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(xAxisPS.scale().invert);
  // TODO: set up brush.move for scale over some threshold (similar to zoom.scaleExtent([1, 100000]) ) to force it to resize along that threshold
  // TODO: implement own control over zoom extent because with embeded functions either it's not possible to move or unzoome after brush or
  //       it's possible to zoom out into a point
  
  scale = xScalePS.copy().domain(domain);
  range = scale.range().map(x => zoomObject_PS.applyX(x));
  domain = range.map(scale.invert);
  xScalePS.domain(domain);
  
  zoomed_PS();
}
function brushedY_PS() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(yAxisPS.scale().invert);
  
  scale = yScalePS.copy().domain(domain.reverse());
  range = scale.range().map(y => zoomObject_PS.applyY(y));
  domain = range.map(scale.invert);
  yScalePS.domain(domain);
  
  zoomed_PS();
}
function handleMouseOver_PS(d, i) {
  var mouse = d3.mouse(this)
  mouse = window.result.type == 'smt' ? mouse : [zoomObject_PS.rescaleX(xScalePS).invert(mouse[0]), zoomObject_PS.rescaleY(yScalePS).invert(mouse[1])]
  var p_count = 0,
      s_count = 0;
      
  if(d3.select(this).attr("class") == "interval") {
    if(window.result.type == 'smt') {
      var sids = selectedStates.filter(x => map_CTX[d.id]['state_ids'].has(""+x))
      p_count = selectedStates.length == 0 ? d.pcov : new Set(sids.map(x => map_PS[Number(x)])).size
      s_count = selectedStates.length == 0 ? d.cov  : sids.length
    } else {
      d3.selectAll(".interval")
        .filter(function() { return Number(d3.select(this).attr("fill-opacity")) >= 0.05 })
        .each(function(dd) {
          for(var j=0, len=dd.data.length; j<len; ++j) {
            const p = dd.data[j]
            if(window.result.type == 'rectangular' && mouse[0] > p.x[0] && mouse[0] < p.x[1] && mouse[1] > p.y[0] && mouse[1] < p.y[1]) {
              p_count++
              s_count += dd.cov
              j = len
            }
          }
        })
    }
  }
  
  mouse = [zoomObject_PS.rescaleX(xScalePS).invert(d3.mouse(this)[0]), zoomObject_PS.rescaleY(yScalePS).invert(d3.mouse(this)[1])]
  infoPanel_PS_lines[0] = "States cov: "+s_count
  infoPanel_PS_lines[1] = "Param. cov: "+p_count
  var off = 2
  for(var v = 0, len = window.bio.params.length; v < len; ++v) {
    var key = window.bio.params[v][0]
    if(key == xDimPS)
      infoPanel_PS_lines[v+off] = key+": "+mouse[0].toFixed(3)+(param_bounds[v] !== null ? [" (",Number(param_bounds[v]).toFixed(3),")"].join("") : "")
    else if(key== yDimPS) 
      infoPanel_PS_lines[v+off] = key+": "+mouse[1].toFixed(3)+(param_bounds[v] !== null ? [" (",Number(param_bounds[v]).toFixed(3),")"].join("") : "")
  }
  off += window.bio.params.length
  for(var v = 0, len = window.bio.vars.length; v < len; ++v) {
    var key = window.bio.vars[v]
    if(key == xDimPS)
      infoPanel_PS_lines[v+off] = key+": "+mouse[0].toFixed(3)+(var_bounds_PS[v] !== null ? [" (",Number(var_bounds_PS[v]).toFixed(3),")"].join("") : "")
    else if(key== yDimPS) 
      infoPanel_PS_lines[v+off] = key+": "+mouse[1].toFixed(3)+(var_bounds_PS[v] !== null ? [" (",Number(var_bounds_PS[v]).toFixed(3),")"].join("") : "")
  }
  d3.select("#infoPanel_PS").property("innerHTML", infoPanel_PS_lines.join("\n"))
}
function handleMouseOut_PS(d, i) {
  var p_count = "unknown",
      s_count = "unknown"
      
  infoPanel_PS_lines[0] = "States cov: "+s_count;
  infoPanel_PS_lines[1] = "Param. cov: "+p_count;
  resetInfoPanel_PS()
}
function redrawClickedPoints() {
  containerPS.selectAll(".marker")
    .attr("d", (d,i) => {
      var x0 = d[0][xDimPS] !== null ? d[0][xDimPS] : d3.min(thrs[xDimPS]),
          x1 = d[0][xDimPS] !== null ? d[0][xDimPS] : d3.max(thrs[xDimPS]),
          y0 = d[0][yDimPS] !== null ? d[0][yDimPS] : d3.min(thrs[yDimPS]),
          y1 = d[0][yDimPS] !== null ? d[0][yDimPS] : d3.max(thrs[yDimPS])
      return "M"+zoomObject_PS.rescaleX(xScalePS)(x0)+","+ zoomObject_PS.rescaleY(yScalePS)(y0)+
             " L"+zoomObject_PS.rescaleX(xScalePS)(x1)+","+ zoomObject_PS.rescaleY(yScalePS)(y1)
    })
    .attr("marker-end", d => {
      if(d[0][xDimPS] === null || d[0][yDimPS] === null) return ""
      else return (d[1] ? "url(#greenCross)" : "url(#redCross)")
    }).moveUp()
    
}
function redrawClickedStates() {
    //TODO: not working properly for dep params
    clicked_states_PS = clicked_points_PS.length == 0 ? [] : Object.keys(map_PS).slice()
    const state_ids = Object.keys(map_PS).length > 0 ? Object.keys(map_PS) : []
    const param_ids = Object.values(map_PS).length > 0 ? Object.values(map_PS) : []
    for(var cp=0,len2=clicked_points_PS.length; cp<len2; ++cp) {
      var act_cp = clicked_points_PS[cp]
      var sinds = []
      if(window.result.type == 'smt') {
        var valid_states = new Set()
        if(Object.values(map_PS).length > 0) {
          var data = Object.assign({}, act_cp[0])
          data['TRUE'] = true
          data['FALSE'] = false
    
          for(var p=0, len=param_ids.length; p<len; ++p) {
            const sid = state_ids[p]
            const pid = param_ids[p]
            
            if(!valid_states.has(sid) && math.eval(window.result.params[pid], data)) {
              valid_states.add(sid)
            }
          }
        }
        sinds = [... valid_states]
      } else {
        //if(d3.select(this).attr("class") == "interval") {
          // we assume all shown and hidden param intervals according to settings by slider values and selected formula
          var sel = d3.selectAll(".interval")
            .filter(d => {
              var result = false
              for(var i=0, len=d.data.length; i<len; ++i) {
                var r = d.data[i],
                    intersect = true,
                    j = 0
                while(intersect && j < window.bio.params.length) {
                  var par = window.bio.params[j++][0]
                  if( act_cp[0][par] !== null && (Number(act_cp[0][par]) > Number(r.all[par][1]) || Number(act_cp[0][par]) < Number(r.all[par][0])) ) intersect = false
                }
                j = 0
                while(intersect && j < window.bio.vars.length) {
                  var par = window.bio.vars[j++]
                  if( act_cp[0][par] !== null && (Number(act_cp[0][par]) > Number(r.all[par][1]) || Number(act_cp[0][par]) < Number(r.all[par][0])) ) intersect = false
                }
                if( intersect ) {
                  result = true
                  map_SS[d.id.replace(/[0-9]+x/,"")].forEach(x => {if(!sinds.includes(""+x)) sinds.push(""+x)} )
                  break
                }
              }
              return !result
            })
        //}
      }
      clicked_states_PS = clicked_states_PS.filter(x => act_cp[1] && sinds.includes(x) || !act_cp[1] && !sinds.includes(x) )
    }
    containerSS.selectAll(".states").attr("stroke-width", d => d.positive.filter(id => clicked_states_PS.includes(""+id)).length > 0 ? hoverStrokeWidth : normalStrokeWidth )
}
function handleMouseClick_PS(dat, ind) {
  var orig_mouse = d3.mouse(this)
  mouse = [Number(zoomObject_PS.rescaleX(xScalePS).invert(orig_mouse[0])), Number(zoomObject_PS.rescaleY(yScalePS).invert(orig_mouse[1]))]
  var data = {}
  window.bio.params.forEach( (d,i) => data[d[0]] = param_bounds[i] );
  window.bio.vars.forEach( (d,i) => data[d] = var_bounds_PS[i] );
  data[xDimPS] = mouse[0]
  data[yDimPS] = mouse[1]
  
  if(window.result.type != 'smt' || d3.select(this).attr("class") == "interval") {  //only for independent parameters it is allowed to click anywhere in PS
    var sinds = new Set()
    clicked_points_PS.push([data, inclusion])
    if(clicked_states_PS.length == 0 && clicked_points_PS.length == 1) clicked_states_PS = Object.keys(map_PS).slice()
    
    var selection = null
    if(d3.select(this).attr("class") == "interval") {
      selection = d3.selectAll(".interval")
        .filter(d => {
          var result = false
          if(window.result.type == 'smt') {
            const r  = Number(radius),  //current points radius in svg coordinates
                  m  = orig_mouse;  //mouse-click point in svg coordinates
            if(window.bio.vars.includes(xDimPS) || window.bio.vars.includes(yDimPS)) {
              if(window.bio.vars.includes(xDimPS)) {
                const cx0 = Number(zoomObject_PS.rescaleX(xScalePS)(d.data[0][xDimPS][0])), //X coordinate for start of this cylinder in svg coordinates
                      cx1 = Number(zoomObject_PS.rescaleX(xScalePS)(d.data[0][xDimPS][1])), //X coordinate for end of this cylinder in svg coordinates
                      cy  = Number(zoomObject_PS.rescaleY(yScalePS)(d.data[0][yDimPS])); //Y coordinate for center of this cylinder in svg coordinates
                if( m[0] >= cx0 && m[0] <= cx1 && m[1] <= cy-r && m[1] >= cy+r ) {
                  result = true
                  map_CTX[parseFloat(d.id)]['state_ids'].forEach(x => {
                    //we need to filter relevant states such that the mouse-click is within their bounds for this particular dimension (in model coordinates)
                    if(mouse[0] >= window.result.states[x][xDimPS_id][0] && mouse[0] <= window.result.states[x][xDimPS_id][1]) sinds.add(""+x)
                  })
                }
              } else {
                const cx = Number(zoomObject_PS.rescaleX(xScalePS)(d.data[0][xDimPS])), //X coordinate for center of this cylinder in svg coordinates
                      cy1 = Number(zoomObject_PS.rescaleY(yScalePS)(d.data[0][yDimPS][1])), //Y coordinate for end of this cylinder in svg coordinates
                      cy0 = Number(zoomObject_PS.rescaleY(yScalePS)(d.data[0][yDimPS][0])); //Y coordinate for start of this cylinder in svg coordinates
                if( m[0] >= cx-r && m[0] <= cx+r && m[1] <= cy0 && m[1] >= cy1 ) {
                  result = true
                  map_CTX[parseFloat(d.id)]['state_ids'].forEach(x => {
                    //we need to filter relevant states such that the mouse-click is within their bounds for this particular dimension (in model coordinates)
                    if(mouse[1] >= window.result.states[x][yDimPS_id][0] && mouse[1] <= window.result.states[x][yDimPS_id][1]) sinds.add(""+x)
                  })
                }
              }
            } else {
              const cx = Number(zoomObject_PS.rescaleX(xScalePS)(d.data[0][xDimPS])), //X coordinate for center of this point in svg coordinates
                    cy = Number(zoomObject_PS.rescaleY(yScalePS)(d.data[0][yDimPS])); //Y coordinate for center of this point in svg coordinates
              if( (m[0]-cx)*(m[0]-cx) + (m[1]-cy)*(m[1]-cy) <= r*r ) {
                result = true
                map_CTX[d.id]['state_ids'].forEach(x => sinds.add(""+x) ) //simply add all states affiliated with selected parametrisation point according to map_CTX
              }
            }
          } else if(window.result.type == 'rectangular') {
            for(var i=0, len=d.data.length; i<len; ++i) {
              const r = d.data[i]
              if(mouse[0] > Number(r.x[0]) && mouse[0] < Number(r.x[1]) && mouse[1] > Number(r.y[0]) && mouse[1] < Number(r.y[1])) {
                result = true
                map_SS[d.id.replace(/[0-9]+x/,"")].forEach(x => sinds.add(""+x) )
                break
              }
            }
          }
          return result
        })
    }
    clicked_states_PS = clicked_states_PS.filter(x => inclusion && sinds.has(x) || !inclusion && !sinds.has(x) )
    containerSS.selectAll(".states").attr("stroke-width", d => d.positive.filter(id => clicked_states_PS.includes(""+id)).length > 0 ? hoverStrokeWidth : normalStrokeWidth )
    
    if(window.result.type != 'smt')
      //in case of indep params cross will be drawn
      containerPS.append("path")
        .datum([data,inclusion])
        .attr("class", "marker")
        .attr("stroke", d => (d[1] ? positive_col : negative_col) )
        .attr("stroke-width", markerWidth)
        .attr("marker-end", d => (d[1] ? "url(#greenCross)" : "url(#redCross)") )
        .attr("d", d => "M"+zoomObject_PS.rescaleX(xScalePS)(d[0][xDimPS])+","+ zoomObject_PS.rescaleY(yScalePS)(d[0][yDimPS])+" l0,0")
    else
      //in case of dep params selected parameterisation(s) will get new color
      selection.attr('fill', inclusion ? positive_col : negative_col )
  }
}
function resettedClick_PS() {
  clicked_states_PS = []
  // all states are set to have normal stroke (as unselected)
  containerSS.selectAll(".states").attr("stroke-width", normalStrokeWidth)
  
  clicked_points_PS = []
  if(window.result.type == 'smt')
    //in case of dep params all parameterisations are set to have default color
    containerPS.selectAll('.interval').attr('fill', reachColor)
  else
    //in case of indep params all crosses are deleted
    containerPS.selectAll(".marker").remove()
}
function reverseLastClick_PS() {
  if(clicked_points_PS.length > 0) {
    clicked_points_PS = clicked_points_PS.slice(0, clicked_points_PS.length-1)
    redrawClickedStates()
    if(window.result.type != 'smt')
      //in case of indep params last cross is deleted
      containerPS.selectAll(".marker").filter((d,i,nodes) => i == nodes.length-1).remove()
  }
}
function changeRadius_PS() {
  if(window.result.type == 'smt') {
    radius = Number(d3.select("#slider_PS_radius").property("value"))
    draw_PS()
  }
}
function addMoreSamplePointsClick_PS() {
  if(window.result.type == 'smt') {
    var nPoints = 100
    // symbolic parameters based on SMT formulae
    for(var p=0; p < window.bio.params.length; p++) {
      if(param_bounds[p] === null) {
        // if the boundary is NOT set a particular context will be generated
        low  = window.bio.params[p][1]
        high = window.bio.params[p][2]
        for(var i=0; i<nPoints; i++)   context_map[window.bio.params[p][0]].push(getRandom(low,high))
      }
    }
    context_map['length'] = d3.max(Object.values(context_map).map(d => d.length))
    ////////////////
    for(var i=context_map["length"]-nPoints, len2=context_map["length"]; i<len2; ++i) {
      var valid_formulae = new Set()
      var valid_states   = new Set()
      var context = {}
      for(var j=0; j<window.bio.params.length; ++j) {
        var pname = window.bio.params[j][0]
        var value = context_map[pname].length > 1 ? context_map[pname][i] : context_map[pname][0] // coordinate of parametrization point
        context[pname] = value
      }
      context['TRUE'] = true
      context['FALSE'] = false

      for(var p=0, len=Object.values(map_PS).length; p<len; ++p) {
        const sid = Object.keys(map_PS)[p]
        const pid = Object.values(map_PS)[p]
        const formula = window.result.params[pid]
        if(valid_formulae.has(pid)) {
          valid_states.add(sid)
        } else {
          if(math.eval(formula, context)) {
            valid_formulae.add(pid)
            valid_states.add(sid)
          }
        }
      }
      map_CTX[i] = { 'ctx': context, 'state_ids': valid_states, 'param_ids': valid_formulae }
    }
    compute_projection()
    draw_PS()
  }
}

function handleMouseOver_SS(d, i) {
  if(d3.select(this).attr("class") == "states") {
    var mouse = [zoomObject_SS.rescaleX(xScaleSS).invert(d3.mouse(this)[0]), zoomObject_SS.rescaleY(yScaleSS).invert(d3.mouse(this)[1])]
    infoPanel_SS_lines[0] = "State id(s): "+d.id.join(", ")
    infoPanel_SS_lines[1] = "Sat. states #: "+d.positive.length
    
    var off = 2
    for(var v = 0, len = window.bio.vars.length; v < len; ++v) {
      var key = window.bio.vars[v]
      if(key == xDimSS)
        infoPanel_SS_lines[v+off] = key+": ["+d3.max(thrs[key].filter(x => x <= mouse[0])).toFixed(3)+", "+d3.min(thrs[key].filter(x => x > mouse[0])).toFixed(3)+"]"
      else if(key== yDimSS) 
        infoPanel_SS_lines[v+off] = key+": ["+d3.max(thrs[key].filter(x => x <= mouse[1])).toFixed(3)+", "+d3.min(thrs[key].filter(x => x > mouse[1])).toFixed(3)+"]"
    }
    d3.select("#infoPanel_SS").property("innerHTML", infoPanel_SS_lines.join("\n"))
  }
}
function handleMouseOut_SS(d, i) {
  infoPanel_SS_lines[0] = "State id(s): none"
  infoPanel_SS_lines[1] = "Sat. states #: none"
  resetInfoPanel_SS()
}
function handleMouseClick_SS(d, i) {
  if(d3.select(this).attr("fill") != noColor) { //non-satisfying states are not selectable
    var sid = d.positive  //array of satisfying state IDs covered by this state
    var pid = new Set()   //starting as Set but finally an Array of satisfiable parameterisation IDs satisfied by states with IDs in 'sid'
    if(window.result.type == 'smt') {
      sid.forEach(s => Object.entries(map_CTX).filter(x => x[1]['state_ids'].has(""+s) || x[1]['state_ids'].has(Number(s))).forEach(x => pid.add(x[0])))
    } else {
      sid.forEach(s => pid.add(s+"x"+map_PS[s]))
    }
    pid = [... pid]
              
    if(d3.select(this).attr("fill") == reachColor) { // better but harder way is to check membership of state IDs in selected states BUT much easier is to check just value of color
      if(selectedStates.length == 0) {
        // first there is need to hide all param intervals (because all was shown before)
        d3.selectAll(".interval").attr("fill-opacity","0")
      }
      // next step is to show only the selected ones
      for(var p=0,len=pid.length; p<len; ++p) {
        if(window.result.type == 'smt') {
          var opac = Number(d3.select("#p"+pid[p]).attr("fill-opacity"))
          d3.select("#p"+pid[p]).attr("fill-opacity", opac+0.1)
        } else {
          var opac = d3.select("#p"+pid[p]).attr("stored-opacity")
          d3.select("#p"+pid[p]).attr("fill-opacity", opac)
        }
        selectedParams.push(pid[p])
      }
      for(var s=0,len=sid.length; s<len; ++s) 
        selectedStates.push(sid[s])
      d3.select(this).attr("fill", positive_col)
    } else if(d3.select(this).attr("fill") == positive_col) { //if state has this color it must be selected already so it is gone be deselected
      selectedParams = selectedParams.filter(x => !pid.includes(x))
      selectedStates = selectedStates.filter(x => !sid.includes(x))
      d3.select(this).attr("fill", reachColor)
      if(selectedStates.length > 0) {
        // hides the selected parameter regardless of others
        for(var p=0,len=pid.length; p<len; ++p) {
          if(window.result.type == 'smt') {
            var opac = Number(d3.select("#p"+pid[p]).attr("fill-opacity"))
            d3.select("#p"+pid[p]).attr("fill-opacity", opac-0.1)
          } else {
            d3.select("#p"+pid[p]).attr("fill-opacity", 0)
          }
        }
      } else {
        // shows all param interval as no state is selected
        d3.selectAll(".interval").attr("fill-opacity", x => d3.select("#p"+x.id).attr("stored-opacity") )
      }
    }
  }
}
function resettedClick_SS() {
  selectedStates = []
  selectedParams = []
  d3.selectAll(".states").attr("fill", x => x.color != noColor ? reachColor : noColor)
  d3.selectAll(".interval").attr("fill-opacity", x => d3.select("#p"+x.id).attr("stored-opacity") )
}

function draw_PS() {
  containerPS.select("#zoomField_PS").remove()
  containerPS.selectAll(".interval").remove()
  
  containerPS.append("rect")
    .attr("id", "zoomField_PS")
    .attr("x", margin.left)
    .attr("y", margin.top)
    .attr("width", width-margin.right-margin.left)
    .attr("height", height-margin.bottom-margin.top)
    .attr("fill", "none")
    .on("click", handleMouseClick_PS)
    .on("mousemove", handleMouseOver_PS)
    .on("mouseout", handleMouseOut_PS);
  
  //var cov_range = projdata.map(x => x.cov)
  //opScale = d3.scaleLinear().domain([d3.min(cov_range),d3.max(cov_range)]).range([0.1,1])
  var opac = 0.1
  
  containerPS.selectAll(".interval")
    .data(projdata)
    .enter()
    .append("path")
    .attr("class", "interval")
    .attr("id", d => "p"+d.id)
    .attr("d", d => {
      var path = "";
      for(var i=0, len=d.data.length; i<len; ++i) {
        var r = d.data[i];
        // Y scale is inverted, therefore, we use the the higher threshold as the first one and the lower threshold as the second one
        if(window.result.type != 'smt') {
          path += " M"+zoomObject_PS.rescaleX(xScalePS)(r.x[0])+","+zoomObject_PS.rescaleY(yScalePS)(r.y[1])+" H"+zoomObject_PS.rescaleX(xScalePS)(r.x[1])+" V"+zoomObject_PS.rescaleY(yScalePS)(r.y[0])+" H"+zoomObject_PS.rescaleX(xScalePS)(r.x[0])
        } else {
          if(window.bio.vars.includes(xDimPS) || window.bio.vars.includes(yDimPS)) {
            if(window.bio.vars.includes(xDimPS)) {
              path += " M"+zoomObject_PS.rescaleX(xScalePS)(r[xDimPS][0])+","+(zoomObject_PS.rescaleY(yScalePS)(r[yDimPS])+radius)+" H"+zoomObject_PS.rescaleX(xScalePS)(r[xDimPS][1])+" V"+(zoomObject_PS.rescaleY(yScalePS)(r[yDimPS])-radius)+" H"+zoomObject_PS.rescaleX(xScalePS)(r[xDimPS][0])
            } else {
              path += " M"+(zoomObject_PS.rescaleX(xScalePS)(r[xDimPS])+radius)+","+zoomObject_PS.rescaleY(yScalePS)(r[yDimPS][0])+" V"+zoomObject_PS.rescaleY(yScalePS)(r[yDimPS][1])+" H"+(zoomObject_PS.rescaleX(xScalePS)(r[xDimPS])-radius)+" V"+zoomObject_PS.rescaleY(yScalePS)(r[yDimPS][0])
            }
          } else
            path += " M"+zoomObject_PS.rescaleX(xScalePS)(r[xDimPS])+","+zoomObject_PS.rescaleY(yScalePS)(r[yDimPS])+" m -"+radius+",0 a"+radius+","+radius+" 0 1,0 "+(2*radius)+",0 a"+radius+","+radius+" 0 1,0 -"+(2*radius)+",0"
        }
      }
      return path;
    })
    .attr("fill", reachColor)
    .attr("fill-opacity", d => ""+(projdata.length == 1 ? 1 : (selectedParams.length > 0 && !selectedParams.includes(d.id) ? 0 : d.cov*opac )))
    .attr("stored-opacity", d => ""+(projdata.length == 1 ? 1 : d.cov*opac))  // this serves as temp storage for case when interval is hidden
    .on("click", handleMouseClick_PS)
    .on("mousemove", handleMouseOver_PS)
    .on("mouseout", handleMouseOut_PS)
}

function draw_SS() {
  containerSS.select("#zoomField_SS").remove()
  containerSS.selectAll(".states").remove()
  
  containerSS.append("rect")
    .attr("id", "zoomField_SS")
    .attr("x", margin.left)
    .attr("y", margin.top)
    .attr("width", width-margin.right-margin.left)
    .attr("height", height-margin.bottom-margin.top)
    .attr("fill", "none")
    .on("click", handleMouseClick_SS)
    .on("mousemove", handleMouseOver_SS)
    .on("mouseout", handleMouseOut_SS);
    
  var opac = 0.2
  
  containerSS.selectAll(".states")
    .data(Object.values(statedata))
    .enter()
    .append("rect")
    .attr("class", "states")
    .attr("id", (d,i) => i)
    .attr("indices", d => d.id)
    .attr("x", d => zoomObject_SS.rescaleX(xScaleSS)(d.x))
    .attr("y", d => zoomObject_SS.rescaleY(yScaleSS)(d.y))
    .attr("width", d => zoomObject_SS.rescaleX(xScaleSS)(d.x1)-zoomObject_SS.rescaleX(xScaleSS)(d.x))
    .attr("height", d => zoomObject_SS.rescaleY(yScaleSS)(d.y1)-zoomObject_SS.rescaleY(yScaleSS)(d.y))
    .attr("fill", d => d.color)
    //.attr("fill-opacity", d => d.opac) 
    .attr("fill-opacity", d => d.id.length > 1 ? d.positive.length*opac : 0.5)
    .attr("stroke", "black")
    .attr("stroke-width", d => d.strokeWidth)
    .attr("pointed", false)
    .on("click", handleMouseClick_SS)
    .on("mouseover", handleMouseOver_SS)
    .on("mouseout", handleMouseOut_SS)

}

    </script>
  </body>

</html>
