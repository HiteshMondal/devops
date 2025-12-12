#!/bin/bash

#Minikube reset script
minikube delete --purge
minikube stop
minikube start --cpus=2 
minikube addons disable storage-provisioner
minikube addons enable storage-provisioner