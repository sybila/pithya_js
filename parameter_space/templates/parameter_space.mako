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
  states = {i: k[u'bounds'] for i,k in enumerate(results[u'states']) }
  params_val = [ k.encode('utf-8') for k in results[u'parameter_values'] ] if results['type'] == 'smt' else results['parameter_values']
  results = {str(k[u'formula']): k[u'data'] for k in results[u'results'] }
  
%>
<html lan"en">
  
  <head>
    <title>Parameter Space</title>
  	<script src="https://d3js.org/d3.v4.js" charset="utf-8"></script>
    <script src="static/mathjs-4.4.2/dist/math.min.js"></script>
    <script src="static/parallel.js-0.2/lib/parallel.js"></script>
    <script src="static/parallel.js-0.2/lib/eval.js"></script>
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
      console.log(window.bio);
      console.log(window.result);
      
      Set.prototype.difference = function(setB) {
          var difference = new Set(this);
          for (var elem of setB) {
              difference.delete(elem);
          }
          return difference;
      };
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
  
    <!--meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1, maximum-scale=1"-->
    <style>
      body {
        background-color: white;
        margin: 0;
        font-family: sans-serif;
        font-size: 18px;
      }
      .containers {
        pointer-events: all;
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
        position: absolute;
        left: 560px;
        height: 100%;
        width: 230px;
        
      }
      #resetZoomBtn_PS {
        position: absolute;
        top: 10px;
      }
      #resetReachBtn_PS {
        position: absolute;
        top: 40px;
      }
      #resetReachOneBtn_PS {
        position: absolute;
        top: 40px;
        left: 75px;
      }
      #checkbox_PS_mode {
        position: absolute;
        top: 40px;
        left: 170px;
      }
      #text_PS_mode {
        position: absolute;
        top: 40px;
        left: 190px;
      }
      #infoPanel_PS {
        position: absolute;
        top: 70px;
        flex-grow: 1;
      }
      #x_axis_PS_div {
        position: absolute;
        top: 160px;
        width: 90px;
      }
      #y_axis_PS_div {
        position: absolute;
        top: 160px;
        width: 90px;
        left: 100px;
      }
      #slidecontainer_PS {
        position: absolute;
        top: 200px;
      }
      #formula_div {
        position: absolute;
        top: 550px;
      }
      
      #resetZoomBtn_SS {
        position: absolute;
        top: 650px;
      }
      #resetReachBtn_SS {
        position: absolute;
        top: 680px;
      }
      #infoPanel_SS {
        position: absolute;
        top: 710px;
        flex-grow: 1;
      }
      #x_axis_SS_div {
        position: absolute;
        top: 800px;
        width: 90px;
      }
      #y_axis_SS_div {
        position: absolute;
        top: 800px;
        width: 90px;
        left: 100px;
      }
      #slidecontainer_SS {
        position: absolute;
        top: 840px;
      }
    </style>

  </head>
  
  <body>
    <div class="widget_panel">
      <button id="resetZoomBtn_PS">Unzoom</button>
<!--      ${save_button()} -->
      <button id="resetReachBtn_PS">Deselect</button>
      <button id="resetReachOneBtn_PS">Deselect last</button>
      <input type="checkbox" value="mode" class="cb" id="checkbox_PS_mode" checked><span id="text_PS_mode">include</span>
      <textarea id="infoPanel_PS" rows="${len(params)+2}" cols="35" wrap="off" disabled></textarea>
      <!-- dynamicly adds sliders with labels for parameters and variables (if more than 2 vars are present) in mako style -->
      <div id="x_axis_PS_div">
        X axis<br>
        <select name="xAxis" id="x_axis_PS" style="width:90px" required>
          % for val in [k[0] for k in params]+vars:
            % if val == params[0][0]:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
      </div>
      <div id="y_axis_PS_div">
        Y axis<br>
        <select name="yAxis" id="y_axis_PS" style="width:90px" required>
          % for val in [k[0] for k in params]+vars:
            % if len(params) > 1 and val == params[1][0]:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
      </div>
      <div id="slidecontainer_PS">
      <hr>
      % for val in params:
        <% 
        min_val  = float(val[1])
        max_val  = float(val[2])
        step_val = abs(max_val-min_val)*0.001
        %>
        % if val[0] == params[0][0] or val[0] == params[1][0]:
        <!--div id="slider_PS_${val[0]}_wrapper" hidden-->
        <div id="slider_PS_${val[0]}_wrapper">
        % else:
        <div id="slider_PS_${val[0]}_wrapper">
        % endif
          par. ${val[0]}: <span id="text_PS_${val[0]}"></span><br>
          <input type="range" min=${min_val} max=${max_val} value=${min_val} step=${step_val} class="slider" id="slider_PS_${val[0]}">
          <input type="checkbox" value="all" class="cb" id="checkbox_PS_${val[0]}" checked>whole
        </div>
      % endfor
      <hr>
      % for val in vars:
        <% 
        min_val  = min(map(float,thrs[val]))
        max_val  = max(map(float,thrs[val]))
        step_val = abs(max_val-min_val)*0.01
        %>
        <div id="slider_PS_${val}_wrapper">
          var. ${val}: <span id="text_PS_${val}"></span><br>
          <input type="range" min=${min_val} max=${max_val} value=${min_val} step=${step_val} class="slider" id="slider_PS_${val}">
          <input type="checkbox" value="all" class="cb" id="checkbox_PS_${val}" checked>whole
        </div>
      % endfor
      </div>
      <div id="formula_div">
        Property<br>
        <select id="formula" style="width:190px" required>
          % for key, val in enumerate(results.keys()):
            % if key == 0:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
        Param<br>
        <select id="param_id" style="width:190px" required>
            <option value="all" selected>all</option>
          % for key, val in enumerate(params_val):
            <option value="${key}">${key}</option>
          % endfor
        </select>
        <hr>
      </div>
      <button id="resetZoomBtn_SS">Unzoom</button>
      <button id="resetReachBtn_SS">Deselect</button>
      <textarea id="infoPanel_SS" rows="${len(vars)+1}" cols="35" wrap="off" disabled></textarea>
      <div id="x_axis_SS_div">
        X axis<br>
        <select name="xAxis" id="x_axis_SS" style="width:90px" required>
          % for val in vars:
            % if val == vars[0]:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
      </div>
      <div id="y_axis_SS_div">
        Y axis<br>
        <select name="yAxis" id="y_axis_SS" style="width:90px" required>
          % for val in vars:
            % if len(vars) > 1 and val == vars[1]:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
      </div>
      <div id="slidecontainer_SS">
      <hr>
      % if len(vars) > 2 :
        % for val in vars:
          <% 
          min_val  = min(map(float,thrs[val]))
          max_val  = max(map(float,thrs[val]))
          step_val = abs(max_val-min_val)*0.01
          %>
          % if val == vars[0] or val == vars[1]:
          <div id="slider_SS_${val}_wrapper" hidden>
          % else:
          <div id="slider_SS_${val}_wrapper">
          % endif
            var. ${val}: <span id="text_SS_${val}"></span><br>
            <input type="range" min=${min_val} max=${max_val} value=${min_val} step=${step_val} class="slider" id="slider_SS_${val}">
          </div>
        % endfor
      % endif
      </div>
    </div>
    
    <script type="text/javascript" charset="utf-8">
   
var xDimPS = document.getElementById("x_axis_PS").value,
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
    var_bounds = [];

// initial parametric bounds are not limited (projection through all parametric dimensions)
window.bio.params.forEach(x => param_bounds.push(null));
// initial bounds of variables are not limited (projection through all dimensions)
window.bio.vars.forEach(x => var_bounds.push(null));

// iteratively adds event listener for variable sliders in PS (according to index)
% for key, val in enumerate(vars):
    (function(i,d) {
        d3.select("#text_PS_"+d).html(d3.select("#slider_PS_"+d).property("value"));
        
        d3.select("#slider_PS_"+d).on("input", function() {
            d3.select("#text_PS_"+d).html(this.value);
            if(! d3.select("#checkbox_PS_"+d).property("checked")) {
                var_bounds[i] = Number(d3.select("#slider_PS_"+d).property("value"));
                result_data_relevance()
                compute_projection()
                draw_PS()
                compute_statedata()
                draw_SS()
                redrawClickedStates()
            }
        });
        d3.select('#checkbox_PS_'+d).on("change", function() {
            if(! d3.select("#checkbox_PS_"+d).property("checked")) {
                var_bounds[i] = Number(d3.select("#slider_PS_"+d).property("value"));
            } else {
                var_bounds[i] = null;
            }
            result_data_relevance()
            compute_projection()
            draw_PS()
            compute_statedata()
            draw_SS()
            redrawClickedStates()
        });
    })(${key},"${val}");
% endfor

// iteratively adds event listener for parameter sliders in PS (according to index)
% for key, val in enumerate(params):
    (function(i,d) {
        d3.select("#text_PS_"+d[0]).html(d3.select("#slider_PS_"+d[0]).property("value"));
        
        d3.select("#slider_PS_"+d[0]).on("input", function() {
            d3.select("#text_PS_"+d[0]).html(this.value);
            if(! d3.select("#checkbox_PS_"+d[0]).property("checked")) {
                param_bounds[i] = Number(d3.select("#slider_PS_"+d[0]).property("value"));
                result_data_relevance()
                compute_projection()
                draw_PS()
                compute_statedata()
                draw_SS()
                redrawClickedStates()
            }
        });
        d3.select('#checkbox_PS_'+d[0]).on("change", function() {
            if(! d3.select("#checkbox_PS_"+d[0]).property("checked")) {
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
        });
    })(${key},${val});
% endfor

// iteratively adds event listener for variable sliders in SS (according to index)
% if len(vars) > 2:
  % for key, val in enumerate(vars):
      (function(i,d) {
          d3.select("#text_SS_"+d).html(d3.select("#slider_SS_"+d).property("value"));
          
          d3.select("#slider_SS_"+d).on("input", function() {
              d3.select("#text_SS_"+d).html(this.value);
              
              compute_statedata()
              draw_SS()
          })
      })(${key},"${val}");
  % endfor
% endif
  
// event listener for change of selectected dimension for X axis in PS
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
  //resettedClick_PS()
  result_data_relevance()
  compute_projection()
  draw_PS()
  redrawClickedPoints()
});

// event listener for change of selectected dimension for Y axis in PS
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
  //resettedClick_PS()
  result_data_relevance()
  compute_projection()
  draw_PS()
  redrawClickedPoints()
});

// event listener for change of selectected dimension for X axis in SS
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
// event listener for change of selectected dimension for Y axis in SS
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

var width = 550,
    height = 450,
    margin = { top: 10, right: 10, bottom: 50, left: 50 },
    edgelen = 7,
    noColor = "transparent",
    reachColor = "rgb(65, 105, 225)", // "royalblue"
    unselectedColor = "rgba(65, 105, 225, 0.5)", // "royalblue" with lower opacity
    neutral_col = "black",
    positive_col = "darkgreen",
    negative_col = "red",
    normalStrokeWidth = 1,
    hoverStrokeWidth = 4,
    markerWidth = 2,
    radius = 4,
    projdata = [],
    statedata = [],
    selectedStates = [],
    selectedParams = [],
    clicked_states_PS = [],
    clicked_points_PS = [],
    zoomObject_PS = d3.zoomIdentity,
    zoomObject_SS = d3.zoomIdentity

// trans example = {
//   0:[0,1],
//   1:[0,3],
//   2:[3],
//   3:[3]
// };

var xScalePS = d3.scaleLinear()
      .domain([d3.min(thrs[xDimPS],parseFloat),
               d3.max(thrs[xDimPS],parseFloat)])
      .range([margin.left, width - margin.right]),
    xScaleSS = d3.scaleLinear()
      .domain([d3.min(thrs[xDimSS],parseFloat),
               d3.max(thrs[xDimSS],parseFloat)])
      .range([margin.left, width - margin.right])

var yScalePS = d3.scaleLinear()
      .domain([d3.min(thrs[yDimPS],parseFloat),
               d3.max(thrs[yDimPS],parseFloat)])
      .range([height - margin.bottom, margin.top]),
    yScaleSS = d3.scaleLinear()
      .domain([d3.min(thrs[yDimSS],parseFloat),
               d3.max(thrs[yDimSS],parseFloat)])
      .range([height - margin.bottom, margin.top])
      
var brushXPS = d3.brushX()
    .extent([[margin.left, 0], [width-margin.right, margin.bottom]])
    .on("end", brushedX_PS),
    
    brushYPS = d3.brushY()
    .extent([[-margin.left, margin.top], [0, height-margin.bottom]])
    .on("end", brushedY_PS),
    
    brushXSS = d3.brushX()
    .extent([[margin.left, 0], [width-margin.right, margin.bottom]])
    .on("end", brushedX_SS),
    
    brushYSS = d3.brushY()
    .extent([[-margin.left, margin.top], [0, height-margin.bottom]])
    .on("end", brushedY_SS)

var zoomPS = d3.zoom()
          //.scaleExtent([1, Infinity])
          //.translateExtent([[0,0],[width,height]])
          .on("zoom", zoomed_PS),
    zoomSS = d3.zoom()
          //.scaleExtent([1, Infinity])
          //.translateExtent([[0,0],[width,height]])
          .on("zoom", zoomed_SS)
          
var svgPS = d3.select("body").append("svg")
      .attr("width", width)
      .attr("height", height),
    svgSS = d3.select("body").append("svg")
      .attr("width", width)
      .attr("height", height)

var containerPS = svgPS.append("g")
        .attr("class", "containers")
        .attr("id","cont_ps")
        //.attr("transform", "translate("+(margin.left)+","+(margin.top)+")")
        .call(zoomPS),
    containerSS = svgSS.append("g")
        .attr("class", "containers")
        .attr("id","cont_ss")
        //.attr("transform", "translate("+(margin.left)+","+(margin.top)+")")
        .call(zoomSS)

var xLabelPS = svgPS.append("text")
      .attr("id", "xLabelPS")
      .attr("class", "label")
      .attr("x", width*0.5)
      .attr("y", height-10)
      .attr("stroke", "black")
      .text(function() { return xDimPS; }),
    xLabelSS = svgSS.append("text")
      .attr("id", "xlabelSS")
      .attr("class", "label")
      .attr("x", width*0.5)
      .attr("y", height-10)
      .attr("stroke", "black")
      .text(function() { return xDimSS; })
var yLabelPS = svgPS.append("text")
      .attr("id", "yLabelPS")
      .attr("class", "label")
      .attr("transform", "rotate(-90)")
      .attr("x", -height*0.5)
      .attr("y", 15)
      .attr("stroke", "black")
      .text(function() { return yDimPS; }),
    yLabelSS = svgSS.append("text")
      .attr("id", "yLabelSS")
      .attr("class", "label")
      .attr("transform", "rotate(-90)")
      .attr("x", -height*0.5)
      .attr("y", 15)
      .attr("stroke", "black")
      .text(function() { return yDimSS; })

var defs = svgPS.append("svg:defs");
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
			.attr("class","clickMark");
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
			.attr("class","arrowHead");

var bottomPanelPS = svgPS.append("g")
    .attr("id", "bPanelPS")
    .attr("class", "panel")
    .attr("transform", "translate("+(0)+","+(height-margin.bottom)+")");
var xAxisPS = d3.axisBottom(xScalePS);
var gXPS = bottomPanelPS.append("g")
    .attr("id", "xAxisPS")
    .attr("class", "axis")
    .call(xAxisPS); // Create an axis component with d3.axisBottom
var gBXPS = bottomPanelPS.append("g")
    .attr("id", "xBrushPS")
    .attr("class", "brush")
    .call(brushXPS);
    
var leftPanelPS = svgPS.append("g")
    .attr("id", "lPanelPS")
    .attr("class", "panel")
    .attr("transform", "translate("+(margin.left)+","+(0)+")");
var yAxisPS = d3.axisLeft(yScalePS);
var gYPS = leftPanelPS.append("g")
    .attr("id", "yAxisPS")
    .attr("class", "axis")
    .call(yAxisPS); // Create an axis component with d3.axisLeft
var gBYPS = leftPanelPS.append("g")
    .attr("id", "xBrushPS")
    .attr("class", "brush")
    .call(brushYPS);

var bottomPanelSS = svgSS.append("g")
    .attr("id", "bPanelSS")
    .attr("class", "panel")
    .attr("transform", "translate("+(0)+","+(height-margin.bottom)+")");
var xAxisSS = d3.axisBottom(xScaleSS);
var gXSS = bottomPanelSS.append("g")
    .attr("id", "xAxisSS")
    .attr("class", "axis")
    .call(xAxisSS); // Create an axis component with d3.axisBottom
var gBXSS = bottomPanelSS.append("g")
    .attr("id", "xBrushSS")
    .attr("class", "brush")
    .call(brushXSS);
    
var leftPanelSS = svgSS.append("g")
    .attr("id", "lPanelSS")
    .attr("class", "panel")
    .attr("transform", "translate("+(margin.left)+","+(0)+")");
var yAxisSS = d3.axisLeft(yScaleSS);
var gYSS = leftPanelSS.append("g")
    .attr("id", "yAxisSS")
    .attr("class", "axis")
    .call(yAxisSS); // Create an axis component with d3.axisLeft
var gBYSS = leftPanelSS.append("g")
    .attr("id", "xBrushSS")
    .attr("class", "brush")
    .call(brushYSS);

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
    while(shown && vid < var_bounds.length) {
      const bound = var_bounds[vid]
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
    var sid = Number(valid_pairs[i][0])
    var pid = Number(valid_pairs[i][1])
    map_PS[sid] = pid
    if(map_SS[pid] === undefined) map_SS[pid] = [sid]
    else map_SS[pid].push(sid)
  }
  if(window.result.type == 'smt') {
    // symbolic parameters based on SMT formulae
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
  }
  console.log(map_PS)
}
    
function compute_projection() {
  projdata = [];
  var state_ids = [],
      param_ids = [];

  if (Object.values(map_PS).length > 0) {
    state_ids = Object.keys(map_PS)
    param_ids = Object.values(map_PS)
      
    if(window.result.type == 'smt') {
      map_CTX = {}
      let prl = new Parallel([... new Array(context_map["length"]).keys()], {env: {
        bio_params: window.bio.params,
        context_map: context_map,
        state_ids: state_ids,
        param_ids: param_ids,
        result_params: window.result.params
      },
        envNamespace: 'env', 
        evalPath: './static/parallel.js-0.2/lib/eval.js'
      })
      //for(var i=0, len2=context_map["length"]; i<len2; ++i) {
      prl.map(function(i) {
        importScripts("https://rawgit.com/josdejong/mathjs/master/dist/math.min.js");
        var valid_formulae = new Set()
        var valid_states   = new Set()
        var context = {}
        console.log(i)
        for(var j=0; j<global.env.bio_params.length; ++j) {
          var pname = global.env.bio_params[j][0]
          var value = global.env.context_map[pname].length > 1 ? global.env.context_map[pname][i] : global.env.context_map[pname][0] // coordinate of parametrization point
          context[pname] = value
        }
        context['TRUE'] = true
        context['FALSE'] = false

        for(var p=0, len=global.env.param_ids.length; p<len; ++p) {
          const sid = global.env.state_ids[p]
          const pid = global.env.param_ids[p]
          const formula = global.env.result_params[pid]
          if(valid_formulae.has(pid)) {
            valid_states.add(sid)
          } else {
            if(math.eval(formula, context)) {
              valid_formulae.add(pid)
              valid_states.add(sid)
            }
          }
        }
/*        map_CTX[i] = { 'state_ids': valid_states, 'param_ids': valid_formulae }
        if(valid_formulae.size > 0) {
          projdata.push({
            "data": [context],
            "id"  : i,
            "cov" : valid_states.size,
            "pcov": valid_formulae.size
          })
        } */
        return({'id': i, 'sids': valid_states, 'pids': valid_formulae, 'ctx': context})
      }).then(function(res) {
        console.log(res)
      });
    } else {
    
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
              x:    (window.bio.vars.includes(xDimPS) ? window.result.states[sid][xDimPS_id] : interval[xDimPS_id]),
              y:    (window.bio.vars.includes(yDimPS) ? window.result.states[sid][yDimPS_id] : interval[yDimPS_id]),
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
  
  for(var i=0, len=Object.values(window.result.states).length; i < len; ++i) {
    var id    = Number(Object.entries(window.result.states)[i][0])
    var state = Object.entries(window.result.states)[i][1]
    
    var shown = true
    var v = 0
    while(shown && v < vars.length) {
      const var_id = window.bio.vars.indexOf(vars[v])
      const thr = Number(d3.select("#slider_SS_"+vars[v]).property("value"))
      if(state[var_id][0] > thr || state[var_id][1] < thr) shown = false
      v++
    }
    
    if(shown) statedata.push({
      "x" : state[xDimSS_id][0],
      "y" : state[yDimSS_id][1],
      "x1": state[xDimSS_id][1],
      "y1": state[yDimSS_id][0],
      "id": id,
      "strokeWidth": clicked_states_PS.includes(""+id) ? hoverStrokeWidth : normalStrokeWidth,
      "color": (state_ids.includes(id) ? (selectedStates.includes(id) ? reachColor : unselectedColor) : noColor)
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
      else
        path += " M"+x(r[xDimPS])+","+y(r[yDimPS])+" m -"+radius+",0 a"+radius+","+radius+" 0 1,0 "+(2*radius)+",0 a"+radius+","+radius+" 0 1,0 -"+(2*radius)+",0"
    };
    return path;
  })
  redrawClickedPoints()
  
  gXPS.call(xAxisPS.scale(x));
  gYPS.call(yAxisPS.scale(y));
  // reset brushes
  gBXPS.call(brushXPS.move, null);
  gBYPS.call(brushYPS.move, null);
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
  var div = document.getElementById("infoPanel_PS");
  var mouse = d3.mouse(this)
  mouse = window.result.type == 'smt' ? mouse : [zoomObject_PS.rescaleX(xScalePS).invert(mouse[0]), zoomObject_PS.rescaleY(yScalePS).invert(mouse[1])]
  var p_count = 0,
      s_count = 0,
      content = "";
      
  if(d3.select(this).attr("class") == "interval") {
    if(window.result.type == 'smt') {
      var sids = selectedStates.filter(x => map_CTX[d.id]['state_ids'].has(""+x))
      p_count = selectedStates.length == 0 ? d.pcov : new Set(sids.map(x => map_PS[Number(x)])).size
      s_count = selectedStates.length == 0 ? d.cov  : sids.length
    } else {
      d3.selectAll(".interval")
        .filter(function() { return Number(d3.select(this).attr("fill-opacity")) > 0 })
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
  content += "States covered: "+s_count;
  content += "\nParametrisations covered: "+p_count;
  for(var v = 0, len = window.bio.params.length; v < len; ++v) {
    var key = window.bio.params[v];
    content += "\n"+key[0]+": "+(key[0] == xDimPS ? mouse[0].toFixed(4) : 
                                  (key[0] == yDimPS ? mouse[1].toFixed(4) : 
                                    (d3.select("#checkbox_PS_"+key[0]).property("checked") ? "["+key[1]+"-"+key[2]+"]" :
                                      d3.select("#slider_PS_"+key[0]).property("value"))));
  }
  
  div.value = content;
}
function handleMouseOut_PS(d, i) {
  var div = document.getElementById("infoPanel_PS");
  var p_count = 0,
      s_count = 0,
      content = "";
      
  content += "States covered: "+s_count;
  content += "\nParametrisations covered: "+p_count;
  for(var v = 0, len = window.bio.params.length; v < len; ++v) {
    var key = window.bio.params[v];
    content += "\n"+key[0]+": "+(key[0] == xDimPS ? "["+zoomObject_PS.rescaleX(xScalePS).domain()[0].toFixed(4)+"-"+zoomObject_PS.rescaleX(xScalePS).domain()[1].toFixed(4)+"]" : 
                                  (key[0] == yDimPS ? "["+zoomObject_PS.rescaleY(yScalePS).domain()[0].toFixed(4)+"-"+zoomObject_PS.rescaleY(yScalePS).domain()[1].toFixed(4)+"]" : 
                                    (d3.select("#checkbox_PS_"+key[0]).property("checked") ? "["+key[1]+"-"+key[2]+"]" :
                                      d3.select("#slider_PS_"+key[0]).property("value"))));
  }
  
  div.value = content;
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
    clicked_states_PS = clicked_points_PS.length == 0 ? [] : Object.keys(map_PS).slice()
    for(var cp=0,len2=clicked_points_PS.length; cp<len2; ++cp) {
      var act_cp = clicked_points_PS[cp]
      var sinds = []
      if(d3.select(this).attr("class") == "interval") {
        if(window.result.type == 'smt') {
          // map_CTX[i] = { 'state_ids': valid_states, 'param_ids': valid_formulae }
//          sinds = [... map_CTX[dat.id]['state_ids']]
        } else {
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
        }
      }
      clicked_states_PS = clicked_states_PS.filter(x => act_cp[1] && sinds.includes(x) || !act_cp[1] && !sinds.includes(x) )
    }
    containerSS.selectAll(".states").attr("stroke-width", (d) => clicked_states_PS.includes(""+d.id) ? hoverStrokeWidth : normalStrokeWidth )
}
function handleMouseClick_PS(dat, ind) {
  var orig_mouse = d3.mouse(this)
  mouse = [Number(zoomObject_PS.rescaleX(xScalePS).invert(orig_mouse[0])), Number(zoomObject_PS.rescaleY(yScalePS).invert(orig_mouse[1]))]
  var data = {}
  window.bio.params.forEach( (d,i) => data[d[0]] = param_bounds[i] );
  window.bio.vars.forEach( (d,i) => data[d] = var_bounds[i] );
  data[xDimPS] = mouse[0]
  data[yDimPS] = mouse[1]
  clicked_points_PS.push([data, inclusion])
  
  var sinds = []
  if(clicked_states_PS.length == 0 && clicked_points_PS.length == 1) clicked_states_PS = Object.keys(map_PS).slice()
  if(d3.select(this).attr("class") == "interval") {
    if(window.result.type == 'smt') {
      // map_CTX[i] = { 'state_ids': valid_states, 'param_ids': valid_formulae }
      sinds = [... map_CTX[dat.id]['state_ids']]
    } else {
      // we assume all shown and hidden param intervals according to settings by slider values and selected formula
      var sel = d3.selectAll(".interval")
        .filter((d) => {
          var result = false
          for(var i=0, len=d.data.length; i<len; ++i) {
            const r = d.data[i]
            if(window.result.type == 'rectangular' && mouse[0] > Number(r.x[0]) && mouse[0] < Number(r.x[1]) && mouse[1] > Number(r.y[0]) && mouse[1] < Number(r.y[1])) {
              result = true
              map_SS[d.id.replace(/[0-9]+x/,"")].forEach(x => {if(!sinds.includes(""+x)) sinds.push(""+x)} )
              break
            }
          }
          return !result
        })
    }
  }
  clicked_states_PS = clicked_states_PS.filter(x => inclusion && sinds.includes(x) || !inclusion && !sinds.includes(x) )
  containerSS.selectAll(".states").attr("stroke-width", (d) => clicked_states_PS.includes(""+d.id) ? hoverStrokeWidth : normalStrokeWidth )
  
  containerPS.append("path")
      .datum([data,inclusion])
      .attr("class", "marker")
      .attr("stroke", d => (d[1] ? positive_col : negative_col) )
      .attr("stroke-width", markerWidth)
      .attr("marker-end", d => (d[1] ? "url(#greenCross)" : "url(#redCross)") )
      .attr("d", d => "M"+zoomObject_PS.rescaleX(xScalePS)(d[0][xDimPS])+","+ zoomObject_PS.rescaleY(yScalePS)(d[0][yDimPS])+" l0,0")
}
function resettedClick_PS() {
  clicked_states_PS = []
  containerSS.selectAll(".states").attr("stroke-width", normalStrokeWidth)
  clicked_points_PS = []
  containerPS.selectAll(".marker").remove()
}
function reverseLastClick_PS() {
  if(clicked_points_PS.length > 0) {
    clicked_points_PS = clicked_points_PS.slice(0, clicked_points_PS.length-1)
    redrawClickedStates()
    containerPS.selectAll(".marker").filter((d,i,nodes) => i == nodes.length-1).remove()
  }
}

function handleMouseOver_SS(d, i) {
  var div = document.getElementById("infoPanel_SS");
  var content = "";
  content = ""+d3.select(this).attr("id")
  div.value = content;
}
function handleMouseOut_SS(d, i) {
  var div = document.getElementById("infoPanel_SS");
  var content = "";
  div.value = content;
}
function handleMouseClick_SS(d, i) {
  if(d3.select(this).attr("fill") != noColor) {
    var sid = d.id
    // map_CTX[i] = { 'state_ids': valid_states, 'param_ids': valid_formulae }
    var pid = window.result.type == 'smt' ? Object.entries(map_CTX).filter(x => x[1]['state_ids'].has(""+sid) || x[1]['state_ids'].has(Number(sid))).map(x => x[0]) : 
              sid+"x"+map_PS[sid]
    if(!selectedStates.includes(sid)) {
      if(selectedStates.length == 0) {
        // first there is need to hide all param intervals (because all was shown before)
        d3.selectAll(".interval").attr("fill-opacity","0")
      }
      // next step is to show only the selected ones
      if(window.result.type == 'smt') {
        for(var p=0,len=pid.length; p<len; ++p) {
          var opac = Number(d3.select("#p"+pid[p]).attr("fill-opacity"))
          d3.select("#p"+pid[p]).attr("fill-opacity", opac+0.1)
          selectedParams.push(pid[p])
        }
      } else {
        var opac = d3.select("#p"+pid).attr("stored-opacity")
        d3.select("#p"+pid).attr("fill-opacity", opac)
        selectedParams.push(pid)
      }
      selectedStates.push(sid)
      d3.select(this).attr("fill", reachColor)
    } else {
      if(window.result.type == 'smt') {
        selectedParams = selectedParams.filter(x => !pid.includes(x))
      } else {
        selectedParams = selectedParams.filter(x => x != pid)
      }
      selectedStates = selectedStates.filter(x => x != sid)
      d3.select(this).attr("fill", unselectedColor)
      if(selectedStates.length > 0) {
        // hides the selected parameter regardless of others
        if(window.result.type == 'smt') {
          for(var p=0,len=pid.length; p<len; ++p)
            d3.select("#p"+pid[p]).attr("fill-opacity", "0")
        } else {
          d3.select("#p"+pid).attr("fill-opacity", "0")
        }
      } else {
        // shows all param interval as no state is selected
        d3.selectAll(".interval").attr("fill-opacity", x => document.getElementById("p"+x.id).getAttribute("stored-opacity") )
      }
    }
  }
}
function resettedClick_SS() {
  selectedStates = []
  selectedParams = []
  d3.selectAll(".states").attr("fill", x => x.color != noColor ? unselectedColor : noColor)
  d3.selectAll(".interval").attr("fill-opacity", x => document.getElementById("p"+x.id).getAttribute("stored-opacity") )
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
        if(window.result.type != 'smt')
          path += " M"+zoomObject_PS.rescaleX(xScalePS)(r.x[0])+","+zoomObject_PS.rescaleY(yScalePS)(r.y[1])+" H"+zoomObject_PS.rescaleX(xScalePS)(r.x[1])+" V"+zoomObject_PS.rescaleY(yScalePS)(r.y[0])+" H"+zoomObject_PS.rescaleX(xScalePS)(r.x[0])
        else
          path += " M"+zoomObject_PS.rescaleX(xScalePS)(r[xDimPS])+","+zoomObject_PS.rescaleY(yScalePS)(r[yDimPS])+" m -"+radius+",0 a"+radius+","+radius+" 0 1,0 "+(2*radius)+",0 a"+radius+","+radius+" 0 1,0 -"+(2*radius)+",0"
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
  
  containerSS.selectAll(".states")
    .data(Object.values(statedata))
    .enter()
    .append("rect")
    .attr("class", "states")
    .attr("id", d => "s"+d.id)
    .attr("x", d => zoomObject_SS.rescaleX(xScaleSS)(d.x))
    .attr("y", d => zoomObject_SS.rescaleY(yScaleSS)(d.y))
    .attr("width", d => zoomObject_SS.rescaleX(xScaleSS)(d.x1)-zoomObject_SS.rescaleX(xScaleSS)(d.x))
    .attr("height", d => zoomObject_SS.rescaleY(yScaleSS)(d.y1)-zoomObject_SS.rescaleY(yScaleSS)(d.y))
    .attr("fill", d => d.color)
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
