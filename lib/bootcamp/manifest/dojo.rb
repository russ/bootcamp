# This is the dojo template
append_file File.join(@project, 'lib', "#{@project}.js") do
<<-JS

(function() {
  // Does anyone know how to write a dojo plugin?
  alert('Hello World');
  
})();
JS
end
